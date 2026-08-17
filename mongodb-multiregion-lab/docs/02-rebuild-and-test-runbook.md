# Rebuild & Test Runbook

This is the manual replay sequence for everything built and tested in
this lab that isn't fully captured by `make apply`/`make site` alone.
See `docs/00-lab-architecture-and-build-plan.md` for the *why*, and
`docs/01-evidence-log.md` for the *results* — this doc is the *how*.

**Honest scope note:** several steps below (hostname switches, the
2+2+1 topology construction, `sh.addShard()`) were done live via
`mongosh` during the original build and were never automated into
Ansible. Re-running `make apply` + `make site` alone will NOT
reproduce these — you have to replay them manually, as documented
here.

---

## Part A — Base infrastructure rebuild

### A0. Prerequisites

```bash
export AWS_PROFILE=psmdb-lab   # add to ~/.bashrc to persist across sessions
cd ~/Databases/mongodb-multiregion-lab
```

You'll need: the SSH key (`~/.ssh/id_ed25519`), your current public IP
for `admin_ssh_cidr` in `terraform.tfvars` (`curl -4 -s ifconfig.me` —
force IPv4), and your Ansible vault password.

### A1. Terraform — everything

```bash
make init
make plan     # review: should show every module (network, main
              # replicaset, arbiter, London-2/Ireland-2/Ireland-3,
              # multiaz x3, configsvr x3, shard1 x3, mongos x3)
make apply
```

### A2. Ansible — OS + PSMDB on everything except mongos

```bash
make site
```

This bootstraps the **main 3-node replica set** automatically
(`rs.initiate()` + admin user creation is scripted in the
`replicaset` role) — but addresses members by **raw private IP**,
not hostname. See A4 below.

### A3. Multi-AZ and sharding layers

```bash
make deploy-multiaz     # bootstraps psmdb-multiaz-lab (3 nodes, London only)
make deploy-sharding    # bootstraps CSRS, then shard1, then starts mongos
```

Same caveat — `multiaz` and `shard1` both bootstrap addressed by raw
IP. CSRS also ends up IP-addressed and was **never actually switched**
to hostnames during the original build (a known, harmless
inconsistency — functional either way, just not visually clean).

### A4. Manual hostname switch — main replica set

SSH into whichever node is PRIMARY (check with `rs.status()` if
unsure), `mongosh` in, then:

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-london:27017"
cfg.members[1].host = "psmdb-ireland:27017"
cfg.members[2].host = "psmdb-paris:27017"
rs.reconfig(cfg)
```

### A5. Manual hostname switch — multiaz

SSH into `psmdb-multiaz-1` (or whichever is PRIMARY):

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-multiaz-1:27017"
cfg.members[1].host = "psmdb-multiaz-2:27017"
cfg.members[2].host = "psmdb-multiaz-3:27017"
rs.reconfig(cfg)
```

### A6. Manual hostname switch — shard1

SSH into `shard1`'s PRIMARY (check `rs.status()`):

```javascript
cfg = rs.conf()
cfg.members[0].host = "psmdb-shard1-london:27017"
cfg.members[1].host = "psmdb-shard1-ireland:27017"
cfg.members[2].host = "psmdb-shard1-paris:27017"
rs.reconfig(cfg)
```

*(CSRS hostname switch was never done in the original build — optional
if you want full consistency; same pattern, target `psmdb-configsvr-*`
hostnames on the CSRS primary.)*

### A7. Register the shard with the cluster

From any `mongos` node:

```javascript
sh.addShard("psmdb-shard1/psmdb-shard1-london:27017,psmdb-shard1-ireland:27017,psmdb-shard1-paris:27017")
sh.status()   // confirm shards: [...] shows psmdb-shard1, active mongoses: 3
```

**Known gotcha:** if `shard1`'s hostname switch (A6) hasn't happened
yet, this fails with `OperationFailed: ... does not belong to replica
set`. Do A6 before A7.

### A8. Verification checklist

```bash
# On any main-cluster node:
rs.status().members.forEach(m => print(m.name, m.stateStr, m.health))
# Expect: 3 healthy members, hostnames not IPs

# On multiaz-1:
rs.status().members.forEach(m => print(m.name, m.stateStr, m.health))
# Expect: 3 healthy members, hostnames not IPs

# On shard1's primary:
rs.status().members.forEach(m => print(m.name, m.stateStr, m.health))
# Expect: 3 healthy members, hostnames not IPs

# On any mongos:
sh.status()
# Expect: 1 shard registered, 3 active mongoses
```

At this point you have the **base topology**: main cluster (3 nodes,
1+1+1), multiaz (3 nodes), and a working sharded cluster (CSRS + 1
shard + 3 mongos). This matches evidence log sections 1-6, 9, 10.

---

## Part B — 2+2+1 topology construction (optional)

Only needed if replaying the arbiter / even-vote / region-majority
demos (evidence log sections 7-8). Skip this if you only need the base
topology from Part A.

**This part has two divergent branches from the same starting point**
— it was built, torn down, and rebuilt differently during the original
session. Pick the branch matching what you want to demo; don't run
both against the same live cluster without reversing the first.

### B0. Starting point (from Part A's main cluster)

Provision the extra nodes first (already in Terraform if you ran A1):
`psmdb-london-2`, `psmdb-ireland-2`, `psmdb-ireland-3`,
`psmdb-paris-arbiter`. All get OS+PSMDB via `make site` (they're in
the `extra_replicaset` / `arbiter` inventory groups).

From the main cluster's PRIMARY:

```javascript
rs.add({ host: "psmdb-london-2:27017", priority: 3, tags: { region: "london" } })
rs.add({ host: "psmdb-ireland-2:27017", priority: 2, tags: { region: "ireland" } })
// wait for both to show SECONDARY/healthy before continuing
rs.remove("psmdb-paris:27017")
```

You're now at **4 voting members** (London x2, Ireland x2) — the
even-vote anti-pattern state. This is the point evidence log section 7
was captured from.

### Branch 1 — Arbiter fix (evidence log section 7, "the fix" + write-concern nuance)

```javascript
rs.addArb("psmdb-paris-arbiter:27017")
```

Now 5 votes (4 data + 1 arbiter), odd, majority-safe. This is the
state for re-running the partition test expecting success instead of
failure, and the `w:1` vs `w:"majority"` nuance test (arbiter fixes
election, not write-concern majority).

### Branch 2 — Region-majority anti-pattern (evidence log section 8)

If coming from Branch 1, first reverse it:
```javascript
rs.remove("psmdb-paris-arbiter:27017")
```

Then add the third Ireland node instead of an arbiter:
```javascript
rs.add({ host: "psmdb-ireland-3:27017", priority: 1, tags: { region: "ireland" } })
```

Now 5 votes (London x2, Ireland x3) — odd total, but Ireland alone
holds majority. This is the region-majority anti-pattern state.

---

## Part C — Test scenario catalog

Each scenario below is independently replayable against the relevant
base topology. Always capture a "before" `rs.status()` first.

### C1. Primary failure — graceful (section 6)
```bash
ssh <primary-node>
sudo systemctl stop mongod   # graceful stop
date -u                       # note timestamp
```
Check `rs.status()` from a surviving node — expect election within
~50ms of the stop, reason `"step up request"` in the log.

### C2. Primary failure — ungraceful (section 6)
```bash
ssh <primary-node>
sudo systemctl kill -s SIGKILL mongod
date -u
```
Expect ~10-11s election delay (full `electionTimeoutMillis`), log
reason `"electionTimeout"`, and `"Startup from clean shutdown?": false`
on restart.

### C3. Even-vote partition demo (section 7)
Requires Branch 1's 4-node state (before adding the arbiter) or after
removing the arbiter from a 5-node state.
```bash
# stop both nodes of one region-pair, e.g. both Ireland nodes
ssh psmdb-ireland "sudo systemctl stop mongod"
ssh psmdb-ireland-2 "sudo systemctl stop mongod"
```
From a surviving node: `rs.status()` shows step-down, then attempt a
write — expect `NotWritablePrimary`. Log shows repeated
`"cannot see a majority"` refusals every ~10s.
**Restore:** start both nodes back up.

### C4. Region-majority anti-pattern demo (section 8)
Requires Branch 2's state (Ireland holds 3-of-5 votes).
```bash
ssh psmdb-ireland "sudo systemctl stop mongod"
ssh psmdb-ireland-2 "sudo systemctl stop mongod"
ssh psmdb-ireland-3 "sudo systemctl stop mongod"
```
Same failure signature as C3, different cause (majority concentrated
in one region, not an even split). **Restore:** start all three back up.

### C5. Arbiter write-concern nuance (section 7)
Requires Branch 1 (arbiter added). Run C3's outage against this
5-node state — election still succeeds (arbiter provides the 3rd
vote), but confirm the actual nuance:
```javascript
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "w1"}, {writeConcern: {w: 1}})              // succeeds instantly
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "wmajority"}, {writeConcern: {w: "majority", wtimeout: 5000}})
  // times out — arbiter doesn't count toward data-bearing majority
```

### C6. Write concern benchmark — main cluster (section 3)
On the PRIMARY:
```bash
python3 write_read_latency.py --op write --write-concern majority --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50,100 --duration 20
```

### C7. Read preference benchmark — main cluster (section 4)
```bash
python3 write_read_latency.py --op read --read-preference primary --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op read --read-preference primaryPreferred --ramp 10,25,50,100 --duration 20
python3 write_read_latency.py --op read --read-preference secondaryPreferred --ramp 10,25,50,100 --duration 20
```

### C8. Multi-AZ benchmarks (section 9)
Same as C6/C7 but run on `psmdb-multiaz-1`, with:
```bash
--uri "mongodb://localhost:27017/?replicaSet=psmdb-multiaz-lab"
```

### C9. mongos regional locality (section 11)
On `psmdb-mongos-london`:
```bash
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50 --duration 20 --uri "mongodb://localhost:27017/"
python3 write_read_latency.py --op write --write-concern 1 --ramp 10,25,50 --duration 20 --uri "mongodb://psmdb-mongos-ireland:27017/"
# repeat both with --write-concern majority
```

### C10. Full regional outage capstone (section 12)
Requires the sharded cluster (Part A complete).
```bash
ssh psmdb-mongos-ireland "sudo systemctl stop mongos"
ssh psmdb-configsvr-ireland "sudo systemctl stop mongod"
ssh psmdb-shard1-ireland "sudo systemctl stop mongod"
date -u
```
Check CSRS and shard1 both hold majority (2-of-3 each), then from
`psmdb-mongos-london`:
```bash
python3 write_read_latency.py --op write --write-concern 1 --concurrency 10 --duration 20 \
  --uri "mongodb://psmdb-mongos-london:27017,psmdb-mongos-ireland:27017,psmdb-mongos-paris:27017/"
```
Expect `errors: 0` — seed-list client routes around the dead region
transparently. **Restore:** start all three Ireland services back up.

---

## Teardown

```bash
make destroy
```

One command tears down everything provisioned in Part A regardless of
which Part B branch or Part C scenarios were run on top — all
replica-set-level state (topology changes, added members, sharding
registration) lives only in the running `mongod`/`mongos` processes,
not in Terraform state, so it's gone the moment the instances are
destroyed. Nothing to clean up separately.
