# PSMDB Multi-Region Lab — Evidence Log

Real, measured results from Topology A (1 replica-set member per region:
London/Ireland/Paris, PSMDB 7.0.39-21). Update this file as each new
scenario is run — this is the source for slide evidence, not memory.

---

## Build status

| Phase | Status | Covers slides |
|---|---|---|
| 1 — Network (3 VPCs, 3 TGWs, peering mesh) | ✅ Done, validated | infra only |
| 2 — Unsharded replica set (region tags, priority) | ✅ Done, PRIMARY=London confirmed | 13–21 |
| 3 — Write concern + read preference benchmarks | ✅ Done (this doc) | 22–25 |
| 4 — Arbiter, primary failure, regional outage, recovery | ⬜ Not started | 16–19, 26, 30–32 |
| 5 — Sharded cluster (CSRS + shard(s) + mongos) | ⬜ Not started | 34–37 |
| 6 — Full evidence pass + rehearsal | ⬜ Not started | — |

---

## 1. Replica set configuration (slides 13, 14, 21)

`rs.conf()` — London primary-preferred (priority 3), region tags on every member:

```javascript
{
  _id: 'psmdb-multiregion-lab',
  members: [
    { _id: 0, host: '10.10.1.107:27017', priority: 3, tags: { region: 'london' } },
    { _id: 1, host: '10.20.1.173:27017', priority: 2, tags: { region: 'ireland' } },
    { _id: 2, host: '10.30.1.199:27017', priority: 1, tags: { region: 'paris' } }
  ]
}
```

## 2. Baseline cross-region latency (slides 15, 24)

Measured via `rs.status().members.forEach(m => print(m.name, m.stateStr, m.pingMs))`
from London (PRIMARY):

| Link | pingMs |
|---|---|
| London → Ireland | 11ms |
| London → Paris | 9ms |

This is real AWS backbone latency, not synthetic — no `tc netem` injection
used (deliberate call: organic latency is more defensible on stage than
a fabricated number, see decision below).

## 3. Write concern comparison: `w:1` vs `w:"majority"` (slides 22, 23, 25)

Benchmark: `write_read_latency.py`, run from the London primary itself
(isolates DB-side cost from client WAN latency), 20s per concurrency step.

### w:"majority"

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---|---|---|---|---|---|
| 10 | 536.4 | 18.2 | 21.63 | 25.47 | 0 |
| 25 | 1181.8 | 19.89 | 28.0 | 33.79 | 0 |
| 50 | 1579.8 | 28.32 | 48.41 | 63.75 | 0 |
| 100 | 1581.8 | 51.04 | 105.94 | 180.25 | 0 |

### w:1

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---|---|---|---|---|---|
| 10 | 2452.2 | 3.61 | 8.24 | 14.07 | 0 |
| 25 | 2342.4 | 9.26 | 21.89 | 36.87 | 0 |
| 50 | 2116.6 | 19.11 | 55.6 | 85.6 | 0 |
| 100 | 1825.5 | 37.13 | 149.96 | 298.44 | 0 |

**Key findings:**
- At low concurrency, `w:1` floor (~3.6ms) vs `w:"majority"` floor (~18.2ms)
  — the ~15ms gap is essentially the measured cross-region RTT. This is
  the direct, defensible evidence for "majority costs real, measurable
  latency in exchange for cross-region durability."
- `w:"majority"` throughput scales cleanly to ~50 concurrency then
  plateaus hard (1580 → 1582 ops/sec from 50→100) — a genuine capacity
  ceiling on this `t3.medium`, not a network effect. Latency keeps
  climbing past that point (queueing), throughput doesn't.
- `w:1` throughput *falls* as concurrency rises (2452 → 1826) — opposite
  direction from majority. Cause: client benchmark and `mongod` share
  the same 2 vCPUs on this node; `w:1`'s fast acks mean threads hammer
  CPU continuously, while `w:"majority"`'s network-wait time releases
  the GIL and incidentally reduces CPU contention. **Caveat for the
  talk:** this is a real finding but is partly an artifact of running
  client + server on the same box — worth stating explicitly if used.
- Zero errors across every run at every concurrency — degrades via
  latency, not failure, under saturation.

## 4. Read preference comparison (slides 22–25, bonus material)

Same benchmark, `--op read`, London primary.

### primary

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 2796.7 | 2.88 | 8.26 | 11.61 |
| 25 | 2642.5 | 7.19 | 22.35 | 32.17 |
| 50 | 2324.3 | 15.77 | 55.66 | 81.58 |
| 100 | 1865.0 | 27.14 | 170.24 | 286.58 |

### primaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 2803.1 | 2.88 | 8.26 | 11.82 |
| 25 | 2668.2 | 7.06 | 22.15 | 32.0 |
| 50 | 2378.7 | 15.63 | 52.49 | 79.06 |
| 100 | 1888.1 | 27.33 | 163.16 | 285.83 |

### secondaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 960.1 | 9.83 | 12.33 | 12.88 |
| 25 | 2377.8 | 9.76 | 12.64 | 13.65 |
| 50 | 3038.6 | 14.45 | 26.31 | 36.32 |
| 100 | 2482.2 | 27.4 | 94.58 | 150.21 |

**Key findings:**
- `primary` and `primaryPreferred` are near-identical — expected, since
  nothing has failed yet. These diverge meaningfully once a failover
  scenario runs (Phase 4) — good setup for that later comparison.
- `secondaryPreferred` floor (~9.8ms) vs `primary` floor (~2.9ms) — same
  cross-region-cost story as the write comparison, now for reads.
- At concurrency 50, `secondaryPreferred` throughput (3038 ops/sec)
  *exceeds* `primary` (2324 ops/sec) — reads offloaded to Ireland/Paris
  free up London's CPU for the client itself. Genuinely useful,
  non-obvious point: distributing reads measurably relieves primary
  load, not just conceptually.
- `secondaryPreferred` @ concurrency 10 (960 ops/sec) breaks the
  otherwise-clean scaling pattern — likely one-time topology-discovery
  overhead per new client connection, amortized away at higher
  concurrency. Flagged as unconfirmed; rerun in isolation before citing
  as a real data point rather than a startup artifact.

## 5. Deliberate decisions worth remembering for the talk narrative

- **No `tc netem` latency injection used.** Considered and reasoned out
  of — organic AWS backbone latency is more credible evidence than a
  fabricated number, and it was good enough (9–11ms) to make the point.
  `latency-inject` role exists in the repo but unused; mention only if
  asked why it's there.
- **10,000 QPS target dropped** — `t3.medium` is burstable, sustained
  extreme load would hit CPU credit exhaustion and throttle in a way
  that misrepresents the topology, not genuinely test it. Ramp-based
  concurrency testing (10→100) was used instead to find a real ceiling
  empirically rather than assume a number.
- Client-and-server-sharing-a-box is a known confound in every number
  above — real, but worth a one-line caveat if presenting the w:1
  throughput-decline finding specifically.

---

## Next up (Phase 4)

- Arbiter toggle (slide 26): add/remove a non-data-bearing voter,
  observe `rs.status()` vote distribution.
- Primary failure + election (slides 16–17): stop mongod on London,
  capture `rs.status()` before/after, election log lines.
- Regional outage (slide 18): stop all members in one region via
  Ansible `--limit`, capture majority-writable state with 2/3 up.
- Same outage, different topology (slide 19): alter `rs.conf()`
  (e.g. different vote distribution), repeat the outage, compare.
- Priority change (slide 21 continuation): flip priorities live, force
  election, capture resulting primary.
- Recovery / RTO-RPO (slides 30–32): restore stopped members, capture
  replication catch-up via `rs.printSecondaryReplicationInfo()` lag
  decreasing to 0, timestamped.
