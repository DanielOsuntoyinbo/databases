# MongoDB Multi-Region Resilience Lab — Detailed Findings

This document preserves the **richer forensic detail** behind the concise experiment-led evidence log.

Use the documents together:

- `01-evidence-log.md` — concise experiment index, measured outcomes and talk-safe conclusions.
- `03-detailed-findings.md` — detailed timelines, benchmark decomposition, anomalies, corrections and implementation notes.
- `evidence-raw/` — underlying raw captures.

Nothing here should be read as a universal MongoDB timing guarantee. Exact values belong to this lab run; the mechanisms and failure modes are the durable lessons.

---

## `RS-01` — Primary failure, election and recovery: full timeline

Raw captures referenced by the original evidence pass include:

- `docs/evidence-raw/rs-status-before-primary-failure-20260816.txt`
- `docs/evidence-raw/election-log-ireland-becomes-primary-20260816.txt`

### Graceful primary stop

| Time (UTC) | Event | Detail |
|---|---|---|
| 2026-08-16 14:43:54 | Baseline captured | London PRIMARY, Ireland `pingMs=11`, Paris `pingMs=8` |
| 14:48:23 → 14:48:39 | London `mongod` stopped | Graceful `systemctl stop`; process shutdown took ~16 s |
| 14:48:23.953 | Election started | `Starting an election due to step up request` — the graceful transition did not wait for a heartbeat timeout |
| 14:48:23.975 | Election won | Ireland obtained the required vote; London was already shutting down |
| 14:48:24.003 | Ireland writable as PRIMARY | `Transition to primary complete; database writes are now permitted` |
| 14:58:38 | London restarted | `systemctl start mongod` |
| 14:58:50.383 | London reclaimed PRIMARY | automatic `priorityTakeover`, ~12.4 s after restart |
| 14:59:30 | Recovery confirmed | Ireland and Paris both showed `replLag: 0 secs` |

Two different recovery measurements were intentionally kept separate:

- **Failover:** the graceful election reached a writable replacement primary in roughly **50 ms once the election started**.
- **Reclaim:** restart → catch-up/eligibility → priority takeover took about **12.4 s** in this idle test.

Those numbers answer different operational questions and should not be averaged into one generic “RTO”.

### Ungraceful primary failure

The same primary was then killed with:

```bash
systemctl kill -s SIGKILL mongod
```

| Time (UTC) | Event |
|---|---|
| 15:13:55 | SIGKILL sent; systemd recorded `Result: signal`, `code=killed, signal=KILL` |
| 15:14:06.131 | Election started — `Starting an election, since we've seen no PRIMARY in election timeout period`; `electionTimeoutPeriodMillis: 10000` |
| 15:14:06.144 | Dry-run vote toward London failed with `HostUnreachable` / `Connection refused` |
| 15:14:06.174 | `Election succeeded, assuming primary role` |
| 15:14:06.222 | `Transition to primary complete; database writes are now permitted` |

**Important decomposition:** kill → election start took about **11.1 s**, while election start → writable took about **91 ms**. The large gap between graceful and abrupt failover in this run was therefore primarily **failure-detection time**, not an intrinsically slow election protocol.

### Unclean restart / WiredTiger recovery

London's restart explicitly recorded:

- `Startup from clean shutdown?: false`
- `Incrementing the rollback ID after unclean shutdown`

WiredTiger recovery took approximately **215 ms** in this idle run:

- ~196 ms log replay
- ~1 ms rollback-to-stable
- ~17 ms checkpoint

This was small because the cluster was nearly idle at crash time. It should **not** be presented as a production recovery expectation: a busier system can have more work to recover.

### Priority-takeover correction

The lab originally assumed London might need a manual election to become PRIMARY again after restart. Testing disproved that assumption: after catching up, the higher-priority London member triggered `priorityTakeover` and reclaimed PRIMARY automatically.

That correction is deliberately preserved because it is more useful than quietly rewriting the original expectation.

### RPO observation and caveat

At the recorded recovery check both secondaries showed `replLag: 0 secs`; no acknowledged `w:"majority"` data loss was observed in these transitions.

The failover test itself ran on an **idle** cluster. The mechanism is useful evidence; the exact durations are not production SLAs. Under sustained write load, shutdown flush time, oplog catch-up time and recovery work can all differ substantially.

---

## `RS-03` + `RS-05` — 2+2 topology, partition and arbiter nuance

### Build history

The lab added two data-bearing members:

- `psmdb-london-2` — second London AZ
- `psmdb-ireland-2` — second Ireland AZ

It also provisioned a standalone Paris arbiter (`t3.micro`). The arbiter was intentionally kept on its own instance rather than as a second `mongod` process on an existing host: the dedicated node made the topology and `rs.conf()` output much easier to explain, while reusing the normal PSMDB installation role.

The arbiter has no special storage mode in `mongod.conf`; arbiter behaviour is a **replica-set configuration property** applied with `rs.addArb()`.

### `RS-03` — four voting data-bearing members

Paris's original data-bearing member was removed, leaving:

```text
psmdb-london:27017     priority 3  votes 1
psmdb-ireland:27017    priority 2  votes 1
psmdb-london-2:27017   priority 3  votes 1
psmdb-ireland-2:27017  priority 2  votes 1
```

London = two votes; Ireland = two votes.

A London↔Ireland partition was represented by stopping both Ireland members. From the surviving London side, only **2 of 4 votes** remained reachable; a majority of three was required.

Observed write attempt:

```javascript
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "partition-demo", ts: new Date()}
)
// MongoServerError[NotWritablePrimary]: not primary
```

The London log repeatedly refused elections over several minutes:

```text
"Not starting an election, since we are not electable"
reason: "Not standing for election because I cannot see a majority (mask 0x1)"
```

Full capture: `docs/evidence-raw/partition-demo-log-london-20260816.txt`.

This repeated refusal is useful evidence of **split-brain protection actively working**, not MongoDB “failing to elect” arbitrarily.

### Recovery observation: equal priority is not deterministic placement

After the Ireland members returned, `psmdb-london-2` became PRIMARY rather than `psmdb-london`, even though both London nodes had priority 3.

**Finding:** equal priority expresses equal preference. It does not promise one particular tied member will always win. A topology that requires a specific preferred member should not leave the relevant members tied.

### `RS-05` — arbiter added

The arbiter was added with:

```javascript
rs.addArb("psmdb-paris-arbiter:27017")
```

`rs.status()` showed `ARBITER`; `rs.conf()` showed `arbiterOnly: true`, `priority: 0`, `votes: 1`.

This produced five **election votes**: four data-bearing members + one arbiter.

The same Ireland-pair outage was repeated. This time the surviving London data nodes plus the Paris arbiter provided **3 of 5 votes**, so an election succeeded and `psmdb-london-2` became PRIMARY.

### Critical nuance: election majority ≠ write-concern majority

During that outage:

```text
psmdb-london:27017         SECONDARY                 health=1
psmdb-ireland:27017        (not reachable/healthy)   health=0
psmdb-london-2:27017       PRIMARY                   health=1
psmdb-ireland-2:27017      (not reachable/healthy)   health=0
psmdb-paris-arbiter:27017  ARBITER                   health=1
```

The arbiter contributed the third **vote** needed for election. It did not provide another data-bearing acknowledgement.

Confirmed directly:

```javascript
// w:1 succeeds: primary's own acknowledgement is enough.
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "post-arbiter-fix-w1", ts: new Date()},
  {writeConcern: {w: 1}}
)
// acknowledged: true

// w:"majority" timed out in the recorded test.
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "post-arbiter-fix-wmajority", ts: new Date()},
  {writeConcern: {w: "majority", wtimeout: 5000}}
)
// MongoWriteConcernError[WriteConcernFailed]: waiting for replication timed out
```

The error contained `n: 1`: the operation had applied on the primary, but the requested durability guarantee was not satisfied within the timeout.

**Talk-safe lesson:** adding an arbiter can restore an election path, but an arbiter is not another copy of the data. Election behaviour and write durability must be reasoned about separately.

---

## `RS-04` — region-majority anti-pattern (2+3)

The arbiter was removed and a third Ireland data-bearing node was added:

```javascript
rs.add({
  host: "psmdb-ireland-3:27017",
  priority: 1,
  tags: { region: "ireland" }
})
```

Result:

```text
London:  psmdb-london, psmdb-london-2                     = 2 votes
Ireland: psmdb-ireland, psmdb-ireland-2, psmdb-ireland-3 = 3 votes
```

Total votes = five, so the topology satisfies the superficial “odd member count” rule. But Ireland alone contains **3 of 5**, the entire majority.

The three Ireland nodes were stopped in sequence on 2026-08-16 around 20:37–20:38 UTC. The surviving London nodes remained healthy but were both SECONDARY and could not form the required majority.

Observed write:

```javascript
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "region-majority-antipattern", ts: new Date()}
)
// MongoServerError[NotWritablePrimary]: not primary
```

The logs again showed repeated:

```text
"Not starting an election, since we are not electable"
reason: "Not standing for election because I cannot see a majority (mask 0x1)"
```

Full capture: `docs/evidence-raw/region-majority-antipattern-log-20260816.txt`.

**Lesson:** odd total votes is incomplete guidance. The resilience question is whether the **required majority survives the failure domain you intend to lose**. A five-member replica set can still be region-fragile if three votes live in one region.

This topology is also a useful basis for planned `REC-01`, but the majority-loss recovery/reconfiguration procedure must not be documented as completed until that new experiment is actually run.

---

## `LAT-01` — Multi-AZ versus multi-region: full measured comparison

Raw output: `docs/evidence-raw/multiaz-benchmark-raw-20260816.txt`.

The comparison replica set is independent of the multi-region set and places three members across London's three AWS AZs (`eu-west-2a/b/c`).

```text
psmdb-multiaz-1  eu-west-2a
psmdb-multiaz-2  eu-west-2b
psmdb-multiaz-3  eu-west-2c
```

Measured `rs.status().members[].pingMs` from `multiaz-1`:

| Link | observed pingMs |
|---|---:|
| multiaz-1 → multiaz-2 | 0 (sub-ms) |
| multiaz-1 → multiaz-3 | 0 (sub-ms) |

Baseline multi-region member latency was **7–11 ms**, versus sub-millisecond inside the London Multi-AZ replica set.

### Multi-AZ `w:"majority"`

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---:|---:|---:|---:|---:|---:|
| 10 | 1060.8 | 8.65 | 14.39 | 20.3 | 0 |
| 25 | 1186.3 | 15.38 | 46.4 | 134.43 | 0 |
| 50 | 1483.5 | 27.88 | 61.91 | 96.31 | 0 |
| 100 | 1425.2 | 53.79 | 136.3 | 242.92 | 0 |

### Multi-AZ `w:1`

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---:|---:|---:|---:|---:|---:|
| 10 | 2357.2 | 3.79 | 8.03 | 13.53 | 0 |
| 25 | 2105.6 | 9.71 | 27.07 | 42.15 | 0 |
| 50 | 1655.4 | 21.39 | 74.19 | 153.04 | 0 |
| 100 | 1638.0 | 36.41 | 183.34 | 333.3 | 0 |

### Comparison findings

1. At concurrency 10, Multi-AZ `w:"majority"` p50 was **8.65 ms** and multi-region `w:"majority"` p50 was **18.2 ms**. The ~9.5 ms difference aligns closely with the measured inter-region RTT.
2. At high concurrency, the two topologies converged toward the same instance-capacity limits. Geography mattered most clearly before local saturation dominated.
3. `w:1` was almost topology-independent: p50 at concurrency 10 was 3.79 ms (Multi-AZ) vs 3.61 ms (multi-region); at concurrency 100, 36.41 ms vs 37.13 ms. That matches the mechanism: `w:1` does not wait for a remote secondary acknowledgement.

### Multi-AZ read-preference results

#### primary

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---:|---:|---:|---:|---:|
| 10 | 2425.3 | 3.31 | 9.66 | 13.75 |
| 25 | 2046.8 | 8.86 | 29.81 | 60.12 |
| 50 | 2103.6 | 16.98 | 61.73 | 93.33 |
| 100 | 1676.0 | 30.81 | 188.14 | 320.06 |

#### primaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---:|---:|---:|---:|---:|
| 10 | 2367.2 | 3.4 | 9.79 | 14.38 |
| 25 | 2065.3 | 9.04 | 29.98 | 51.48 |
| 50 | 2093.8 | 17.09 | 60.82 | 92.59 |
| 100 | 1619.4 | 31.44 | 197.29 | 331.73 |

#### secondaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---:|---:|---:|---:|---:|
| 10 | 3161.4 | 2.58 | 6.69 | 9.68 |
| 25 | 2961.2 | 6.23 | 20.76 | 30.96 |
| 50 | 2122.3 | 15.39 | 59.66 | 170.94 |
| 100 | 2265.3 | 25.78 | 130.92 | 220.8 |

Two useful confirmations:

- `primary` reads were broadly topology-independent because the operation stayed on the primary.
- `secondaryPreferred` exposed the same network-distance effect as majority writes: at concurrency 10, Multi-AZ p50 was **2.58 ms** vs **9.83 ms** in the multi-region set.

The surprisingly strong secondaryPreferred throughput in some runs is affected by the benchmark-client placement and shared CPU, so treat it as a lab observation rather than a universal recommendation.

---

## Sharded-cluster build detail

Raw build log: `docs/evidence-raw/sharding-build-raw-20260817.txt`.

Scope was intentionally kept to what the resilience experiment needed:

- CSRS: three members, one per region
- shard1: three members, one per region
- three `mongos` routers, one per region

A second shard was deliberately skipped because it did not materially improve the regional-resilience question being tested.

### Real build issue: member-name mismatch

The shard1 bootstrap initially used raw private IP addresses rather than the region-readable aliases already used by other replica sets. `sh.addShard()` failed because the host list supplied to `mongos` did not match the replica-set member identity.

The issue was fixed with the same controlled `rs.reconfig()` hostname-normalization pattern used elsewhere in the lab.

After registration, `sh.status()` showed one active shard and all three `mongos` routers connected:

```text
shards: [{
  _id: 'psmdb-shard1',
  host: 'psmdb-shard1/psmdb-shard1-ireland:27017,psmdb-shard1-london:27017,psmdb-shard1-paris:27017',
  state: 1
}]
active mongoses: [{ '7.0.39-21': 3 }]
```

Keeping this build issue is useful for anyone reproducing the lab: MongoDB replica-set identity and the hostnames passed to `sh.addShard()` need to agree.

---

## Sharded routing locality benchmark

Raw output: `docs/evidence-raw/mongos-locality-benchmark-raw-20260817.txt`.

The benchmark client ran on the London `mongos` host and was deliberately pinned first to local London `mongos`, then to remote Ireland `mongos`. The shard primary was in London. This isolates router-location cost; it is **not** how a normal resilient application should connect, because a real client should use multiple router endpoints.

### `w:1`

| Target | concurrency | ops/sec | p50 ms |
|---|---:|---:|---:|
| Local London | 10 | 2605.7 | 3.36 |
| Local London | 25 | 2508.9 | 8.53 |
| Local London | 50 | 2107.3 | 18.65 |
| Remote Ireland | 10 | 415.9 | 23.24 |
| Remote Ireland | 25 | 1052.7 | 23.12 |
| Remote Ireland | 50 | 2084.8 | 23.07 |

### `w:"majority"`

| Target | concurrency | ops/sec | p50 ms |
|---|---:|---:|---:|
| Local London | 10 | 462.6 | 20.57 |
| Local London | 25 | 1161.1 | 20.77 |
| Local London | 50 | 1908.6 | 24.61 |
| Remote Ireland | 10 | 217.9 | 44.88 |
| Remote Ireland | 25 | 553.8 | 44.36 |
| Remote Ireland | 50 | 1081.3 | 44.15 |

### Findings

- Router locality mattered in the pinned test: remote routing introduced a large fixed latency floor.
- Remote p50 stayed around ~23 ms for `w:1` across the tested concurrency levels while local latency rose with load.
- `w:"majority"` added the shard replica-set replication wait on top of either router path; it did not change the basic local-vs-remote conclusion.

Again, the test intentionally pinned one router at a time for measurement. The actual resilience test below used a multi-router seed list.

---

## `SH-01` — full sharded regional outage: detailed proof

Raw capture: `docs/evidence-raw/regional-outage-capstone-raw-20260817.txt`.

The experiment stopped **all three Ireland sharding-layer components at the same time**:

- Ireland `mongos`
- Ireland CSRS member
- Ireland shard1 member

Timestamp: **2026-08-17 16:15:08 UTC**.

### Baseline

```text
CSRS:
10.10.1.182:27017 PRIMARY
10.20.1.14:27017  SECONDARY
10.30.1.38:27017  SECONDARY

shard1:
psmdb-shard1-london:27017  PRIMARY
psmdb-shard1-ireland:27017 SECONDARY
psmdb-shard1-paris:27017   SECONDARY
```

### During outage

CSRS retained two healthy members:

```text
10.10.1.182:27017 PRIMARY                    health=1
10.20.1.14:27017  (not reachable/healthy)    health=0
10.30.1.38:27017  SECONDARY                  health=1
```

Shard1 retained two healthy members:

```text
psmdb-shard1-london:27017   PRIMARY                  health=1
psmdb-shard1-ireland:27017  (not reachable/healthy)  health=0
psmdb-shard1-paris:27017    SECONDARY                health=1
```

### Client proof

From London, the client seed list deliberately still included the **dead Ireland router**:

```bash
python3 write_read_latency.py --op write --write-concern 1 \
  --concurrency 10 --duration 20 \
  --uri "mongodb://psmdb-mongos-london:27017,psmdb-mongos-ireland:27017,psmdb-mongos-paris:27017/"
```

Recorded result:

```json
{
  "op": "write",
  "write_concern": 1,
  "concurrency": 10,
  "duration_sec": 20,
  "count": 26044,
  "errors": 0,
  "throughput_ops_sec": 1302.2,
  "latency_ms": {
    "min": 1.35,
    "p50": 2.08,
    "p95": 19.33,
    "p99": 25.41,
    "max": 231.92,
    "mean": 7.67
  }
}
```

The strongest directly supported statement is: **the tested application write workload continued with zero errors while the Ireland region's router, CSRS member and shard member were unavailable**.

Do not over-generalize the `1302.2 ops/sec` figure as universal “normal throughput” without a strictly comparable healthy-baseline run. The zero-error application outcome and the surviving layer states are the more defensible resilience evidence.

### Recovery

All three Ireland services were restarted. Subsequent CSRS and shard1 status showed the members healthy again.

**Capstone lesson:** “multi-region” was not sufficient by label. The outage was survived because the CSRS retained its majority, shard1 retained its majority, and the client still had reachable `mongos` endpoints.

---

## Experimental decisions and caveats worth preserving

### Organic latency instead of synthetic delay

The lab considered `tc netem`, and the Ansible role remains available, but the evidence selected for the talk used real AWS inter-region latency. That decision avoids presenting fabricated latency as though it were the observed production-like path.

### 10,000-QPS target deliberately dropped

The test nodes are `t3.medium` burstable instances. Driving an arbitrary 10k-QPS target risked testing CPU-credit behaviour more than topology. The benchmark therefore used a concurrency ramp to observe where the actual lab saturated.

### Client and server share a box in several benchmarks

This is an explicit confound. Some throughput effects — especially `w:1` declining at higher concurrency and some secondary-read behaviour — are influenced by the benchmark process and `mongod` competing for the same CPU. Keep those observations, but do not present them as pure topology effects.

### Preserve anomalies rather than smoothing them away

The `secondaryPreferred` concurrency-10 result in the multi-region read test did not match the otherwise clean pattern. It was flagged as potentially topology-discovery/startup related and should be rerun before being used as a standalone claim.

This is intentional evidence discipline: anomalous data should be marked, not silently discarded.

---

## Planned extensions

### `REC-01` — recover after majority loss

Planned 2+3 experiment. Preserve the same evidence standard:

1. healthy `rs.conf()` / `rs.status()`
2. loss of the three-member region
3. proof that 2/5 cannot elect a writable primary
4. exact recovery/reconfiguration action
5. data-safety implications
6. recovered topology and client validation

### `DR-01` — disaster recovery when HA is insufficient

Planned backup/PITR restore exercise. Keep the evidence distinct from normal replica-set failover and record the restore source, procedure, validation, observed RTO and resulting RPO only after a repeatable recovery test has been run.
