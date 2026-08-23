# MongoDB Multi-Region Resilience Lab — Rebuild & Test Runbook

This document is the **how**: rebuild the environment, select a topology, run an experiment and verify recovery.

- Architecture and design rationale: `00-lab-architecture-and-build-plan.md`
- Measured results and interpretation: `01-evidence-log.md`
- Raw captures: `evidence-raw/`

> **Reproducibility note:** infrastructure and baseline configuration are automated, but several experimental topology transitions were originally performed live with `mongosh`. They are documented explicitly below. `make apply` + `make site` alone does not recreate every experimental state.

---

## Part A — Build the base lab

### A0. Prerequisites

```bash
export AWS_PROFILE=psmdb-lab
cd ~/Databases/mongodb-multiregion-lab
```

You need the SSH key, your current public IP configured as `admin_ssh_cidr`, the Ansible vault password, Terraform and Ansible.

### A1. Provision infrastructure

```bash
make init
make plan
make apply
```

Review the plan before applying. The complete lab includes the regional network, baseline replica-set nodes, extra members used by voting-topology experiments, the Multi-AZ comparison nodes, CSRS, shard replica-set members and `mongos` routers.

### A2. Configure PSMDB

```bash
make site
```

This bootstraps the main three-member replica set automatically. The initial bootstrap may use private IP addresses; the hostname normalization below makes experiment output easier to read.

### A3. Deploy Multi-AZ and sharded layers

```bash
make deploy-multiaz
make deploy-sharding
```

### A4. Normalize main replica-set member names

From the current PRIMARY:

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-london:27017"
cfg.members[1].host = "psmdb-ireland:27017"
cfg.members[2].host = "psmdb-paris:27017"
rs.reconfig(cfg)
```

### A5. Normalize Multi-AZ member names

From the Multi-AZ PRIMARY:

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-multiaz-1:27017"
cfg.members[1].host = "psmdb-multiaz-2:27017"
cfg.members[2].host = "psmdb-multiaz-3:27017"
rs.reconfig(cfg)
```

### A6. Normalize shard member names

From shard1's PRIMARY:

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-shard1-london:27017"
cfg.members[1].host = "psmdb-shard1-ireland:27017"
cfg.members[2].host = "psmdb-shard1-paris:27017"
rs.reconfig(cfg)
```

The CSRS hostname switch was not part of the original evidence pass; it is optional for consistency. Skipping this step on shard1 specifically caused `sh.addShard()` to fail in A7 — see the note there.

### A7. Register shard1

From any `mongos`:

```javascript
sh.addShard("psmdb-shard1/psmdb-shard1-london:27017,psmdb-shard1-ireland:27017,psmdb-shard1-paris:27017")
sh.status()
```

If `sh.addShard()` reports that a member does not belong to the replica set, complete A6 first — this is exactly what happened during the original build: the seed list used hostnames while the replica set's own config still held private IPs, and the error message named the mismatch directly.

### A8. Verify the base lab

```javascript
// main replica set
rs.status().members.forEach(m => print(m.name, m.stateStr, m.health))
```

Verify separately on the main replica set, Multi-AZ replica set and shard1 that all expected members are healthy. From `mongos`, run `sh.status()` and confirm shard1 is registered and the routers are active.

At this point the reusable baseline is ready: **1+1+1 main replica set + Multi-AZ comparison replica set + CSRS + shard1 + regional mongos routers**.

---

## Part B — Select an alternate voting topology

Only use this section for experiments that need a topology other than the baseline 1+1+1 replica set.

### B0. Build the 2+2 starting state

Ensure the extra nodes are provisioned/configured, then from the main PRIMARY:

```javascript
rs.add({ host: "psmdb-london-2:27017", priority: 3, tags: { region: "london" } })
rs.add({ host: "psmdb-ireland-2:27017", priority: 2, tags: { region: "ireland" } })
// Wait until both are healthy SECONDARY members.
rs.remove("psmdb-paris:27017")
```

You now have **four voting data-bearing members: London x2 + Ireland x2**. This is the `RS-03` even-vote state.

### B1. Add an arbiter — restore election majority (`RS-05`)

```javascript
rs.addArb("psmdb-paris-arbiter:27017")
```

This creates five votes: four data-bearing members plus one arbiter.

The purpose is precise: **the arbiter can contribute a vote to an election, but it does not add another copy of the data**. Do not treat this as a general durability fix.

### B2. Build the region-majority anti-pattern (`RS-04`)

If the arbiter is present, remove it first:

```javascript
rs.remove("psmdb-paris-arbiter:27017")
```

Then add the third Ireland data-bearing member:

```javascript
rs.add({ host: "psmdb-ireland-3:27017", priority: 1, tags: { region: "ireland" } })
```

The result is **London x2 + Ireland x3**. Five votes is an odd total, but one failure domain holds the entire majority. `RS-04` demonstrates why member count alone is not the resilience model.

`REC-01` reuses this same 2+3 shape, but as of that experiment it was built as an **independent, dedicated topology** rather than by extending the running main cluster — see the Appendix for why, and for the scoped-Terraform-build procedure that made it possible without provisioning the full lab.

---

## Part C — Run the experiments

Before every experiment:

1. Record `date -u`.
2. Capture `rs.conf()` where topology matters.
3. Capture a healthy `rs.status()` before the failure/action.
4. Run the action.
5. Capture the MongoDB state, relevant logs and client outcome.
6. Restore the environment and verify the intended steady state — except `REC-01`, which is deliberately irreversible; see that section.

### `RS-01` — Primary failure and election

**Question:** What changes between a graceful primary stop and an abrupt failure?

Graceful:

```bash
ssh <primary-node>
sudo systemctl stop mongod
date -u
```

Capture the surviving members' state and election logs. The measured evidence in this lab showed the graceful stop triggering a step-up election without waiting for the full election timeout.

Ungraceful:

```bash
ssh <primary-node>
sudo systemctl kill -s SIGKILL mongod
date -u
```

Capture the same evidence. In the recorded run, election start followed the election-timeout path; see `01-evidence-log.md` for the measured timings rather than assuming those numbers for every environment.

Restore the stopped member and confirm it rejoins and catches up.

---

### `RS-02` — Regional failure with majority preserved

**Question:** If one failure domain disappears, do the surviving voting members still form a majority?

Use the baseline 1+1+1 topology. Stop the member in one region and inspect `rs.status()` plus a client write from the surviving service path.

The expected design property is not "three regions are resilient"; it is **the surviving topology still has the required majority**.

---

### `RS-03` — Even-vote topology

Requires the four-member 2+2 state from B0.

```bash
ssh psmdb-ireland "sudo systemctl stop mongod"
ssh psmdb-ireland-2 "sudo systemctl stop mongod"
```

Inspect `rs.status()`, attempt a write and capture election logs. The recorded evidence shows the surviving 2-of-4 side unable to elect a writable primary.

Restore both services before moving to another topology.

---

### `RS-04` — Region-majority anti-pattern

Requires B2: London x2 + Ireland x3.

```bash
ssh psmdb-ireland "sudo systemctl stop mongod"
ssh psmdb-ireland-2 "sudo systemctl stop mongod"
ssh psmdb-ireland-3 "sudo systemctl stop mongod"
```

Inspect the surviving London members and attempt a write. This demonstrates a different path to the same availability failure: the total vote count is odd, but the lost region contained the majority.

Restore all three Ireland services after capture.

---

### `RS-05` — Arbiter and election majority

Requires B1.

Repeat the relevant two-data-member outage with the arbiter available. Capture election state first, then separately test write concern:

```javascript
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "w1"}, {writeConcern: {w: 1}})

db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "wmajority"}, {writeConcern: {w: "majority", wtimeout: 5000}})
```

The experiment separates two ideas that are easy to conflate: **election majority** and **data-bearing acknowledgement**.

---

### `WC-01` — `w:1` vs `w:"majority"`

Run from the London primary for the recorded benchmark methodology:

```bash
python3 write_read_latency.py --op write --write-concern majority --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50,100 --duration 20
```

Do not copy the existing latency numbers into a new environment and call them expected results. Capture the new run and compare it with the evidence log.

---

### `READ-01` — Read preference

```bash
python3 write_read_latency.py --op read --read-preference primary --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op read --read-preference primaryPreferred --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op read --read-preference secondaryPreferred --ramp 10,25,50,100 --duration 20
```

Capture throughput and latency together; routing a read elsewhere can change both network cost and where CPU work occurs.

---

### `LAT-01` — Multi-region vs Multi-AZ

Run the same benchmark methodology against the Multi-AZ replica set:

```bash
--uri "mongodb://localhost:27017/?replicaSet=psmdb-multiaz-lab"
```

Compare with the multi-region results using the same operation, write concern/read preference and concurrency. The comparison is more useful than treating either latency number in isolation.

---

### `SH-01` — Sharded-cluster regional outage

Requires the complete sharded cluster.

Simulate loss of Ireland across the routing, metadata and shard layers:

```bash
ssh psmdb-mongos-ireland "sudo systemctl stop mongos"
ssh psmdb-configsvr-ireland "sudo systemctl stop mongod"
ssh psmdb-shard1-ireland "sudo systemctl stop mongod"
date -u
```

Verify that the surviving CSRS members still form majority and that shard1 still forms majority. Then test through the client seed list from London:

```bash
python3 write_read_latency.py --op write --write-concern 1 --concurrency 10 --duration 20 \
  --uri "mongodb://psmdb-mongos-london:27017,psmdb-mongos-ireland:27017,psmdb-mongos-paris:27017/"
```

Capture the client result and the surviving CSRS/shard states. Restore all Ireland services and verify the cluster returns to steady state.

---

### `SH-02` — mongos regional locality

**Question:** does router choice matter, given a `mongos` holds no data of its own?

Run the benchmark from one region's `mongos` host, once against its own local router and once against a deliberately remote one — same client location both times, only the target changes:

```bash
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50 --duration 20 --uri "mongodb://localhost:27017/"
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50 --duration 20 --uri "mongodb://psmdb-mongos-ireland:27017/"
```

Repeat both with `--write-concern majority` for a second data point. No `replicaSet=` parameter is needed — `mongos` is a single connection point, not itself a replica set member.

Note which region currently holds shard1's primary before running this, since the result is directional (cost depends on router-to-primary distance, not router-to-router distance).

---

### `REC-01` — Recover after majority loss

Target topology: **London x2 + Ireland x3**, built as a dedicated scoped rebuild (see Appendix) rather than by extending a running main cluster via Part B, since this experiment was run after a full teardown and only needed these 5 nodes.

**This is deliberately irreversible — do not restore Ireland expecting a clean rejoin.** Unlike every other experiment in this runbook, the point of `REC-01` is to demonstrate MongoDB's recovery procedure for a *permanent* majority loss, and to show that the recovery is a one-way door.

1. Capture a healthy baseline `rs.status()` on all 5 members.
2. Stop all 3 Ireland members simultaneously:
   ```bash
   ssh psmdb-ireland "sudo systemctl stop mongod"
   ssh psmdb-ireland-2 "sudo systemctl stop mongod"
   ssh psmdb-ireland-3 "sudo systemctl stop mongod"
   date -u
   ```
3. Confirm the lockout — same signature as `RS-04` (no writable primary, London's 2 votes short of the old config's 3-vote majority).
4. Run the forced reconfiguration on a surviving member:
   ```javascript
   cfg = rs.conf()
   cfg.members = cfg.members.filter(m => ["psmdb-london:27017", "psmdb-london-2:27017"].includes(m.host))
   cfg.version += 1
   rs.reconfig(cfg, { force: true })
   ```
5. Confirm recovery — a primary should be elected among the 2 survivors within seconds, and a `w:"majority"` write should succeed against the new (2-vote) majority.
6. **Prove irreversibility** — restart one of the excluded Ireland members and connect to it directly:
   ```javascript
   rs.status()
   // expect: MongoServerError[InvalidReplicaSetConfig]
   ```
   The excluded member is running and has its data, but cannot rejoin — it still holds the old config, which the survivors have moved on from.
7. Tear down this scoped topology when done (`make destroy` against just these resources, or the full lab teardown if nothing else is running).

**Safety note for anyone reusing this procedure:** only use `force: true` when the missing majority is confirmed permanently gone. If the "lost" nodes are only temporarily unreachable and come back while still holding the old config, forcing a reconfiguration first can produce genuine split-brain rather than the clean lockout demonstrated here.

---

### `DR-01` — Disaster recovery when HA is insufficient — planned

This is not a completed lab scenario yet. It will cover backup/PITR-based service recovery separately from replica-set high availability, with measured RTO/RPO only after a repeatable restore test exists.

---

## Part D — Evidence capture standard

For future experiments, prefer an experiment-oriented evidence directory/name rather than slide-oriented filenames. For example:

```text
evidence-raw/
└── REC-01-majority-loss-recovery/
    ├── 01-before-rs-conf.txt
    ├── 02-before-rs-status.txt
    ├── 03-majority-lost.txt
    ├── 04-reconfiguration.txt
    ├── 05-recovered-rs-status.txt
    └── 06-client-validation.txt
```

Existing evidence does not need to be renamed just to satisfy this convention; preserve working references and apply the structure to new experiments first.

---

## Appendix — Scoped rebuilds via `terraform -target`

Some experiments (`REC-01`) don't need the full lab — just a handful of data-bearing nodes. `terraform -target` supports this, but has a real limitation worth knowing before it costs you time: **any output referencing a resource outside the targeted set is dropped from state entirely, not just that key** — and `try()` cannot rescue it, because the pruning happens at the plan-graph level, before `try()`'s runtime error-catching ever runs.

**Symptom:** `terraform output <name>` returns `Error: Output "<name>" not found`, even immediately after a clean, successful `apply`.

**Workaround:** read the actual values out of state instead of through outputs — the resource genuinely exists, only the output's evaluation was pruned:

```bash
terraform state show 'module.replicaset_london.aws_instance.node[0]' | grep -E "public_ip|private_ip"
```

Then hand-build a minimal static Ansible inventory from those values (bypassing `psmdb.py`, which depends on `terraform output -json`). Match the structure the target role expects — check the relevant role's tasks and template for exactly which hostvars and group structure are required (for the main `replicaset` role: `replicaset_member_id`, `replicaset_priority`, `region`, `private_ip`, plus a `region_<name>` child group for its `delegate_to` targets). Run directly against the hand-built file rather than through `make site` (which regenerates `hosts.yml` via `psmdb.py` and would overwrite it):

```bash
ansible-playbook -i inventory/hosts-<scenario>.yml playbooks/site.yml --ask-vault-pass
```

**A smaller, related gotcha:** after a full `make destroy` + rebuild, both `/etc/hosts` and `~/.ssh/known_hosts` on your workstation will still have stale entries under the *same hostnames*, pointing at the old, now-destroyed IPs/host keys. SSH will either silently try the dead IP first (a duplicate `/etc/hosts` line) or refuse to connect with a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning — which is correct, since it genuinely did change. Fix both before troubleshooting anything else if a rebuilt node seems unreachable:

```bash
sudo sed -i '/psmdb-<name>/d' /etc/hosts   # remove ALL old lines first, then re-add fresh ones
ssh-keygen -f ~/.ssh/known_hosts -R psmdb-<name>   # per hostname
```

---

## Teardown

```bash
make destroy
```

Terraform removes the provisioned infrastructure. Replica-set topology changes and sharding registration stored only in the running database processes disappear with those instances, so no separate topology cleanup is required after destruction.
