# MongoDB Multi-Region Resilience Lab — Evidence Log

This is the **measured record** of the lab: configuration, observed behaviour, timings, benchmark results and corrections discovered during testing.

The Percona Live 2026 slides use selected results from this file, but the evidence is organized around stable experiment IDs rather than slide numbers. Raw captures remain in `docs/evidence-raw/`.

PSMDB version for the recorded evidence: **7.0.39-21**.

> Treat measured numbers as results from this lab environment, not universal MongoDB constants. The repeatable mechanism is usually more important than the exact timing.

---

## Evidence status

| Experiment | Status | What has been captured |
|---|---|---|
| `RS-01` Primary failure and election | ✅ | graceful + SIGKILL failure, election logs, recovery |
| `RS-02` Regional failure with majority preserved | ✅ | regional-loss behaviour in the distributed topology |
| `RS-03` Even-vote topology | ✅ | 2+2 majority loss and write unavailability |
| `RS-04` Region-majority anti-pattern | ✅ | 2+3 placement showing majority concentrated in one region |
| `RS-05` Arbiter and election majority | ✅ | election-vote behaviour + write-concern nuance |
| `WC-01` `w:1` vs `w:"majority"` | ✅ | throughput and p50/p95/p99 latency |
| `READ-01` Read preference | ✅ | primary / primaryPreferred / secondaryPreferred benchmark |
| `LAT-01` Multi-region vs Multi-AZ | ✅ | measured latency comparison |
| `SH-01` Sharded regional outage | ✅ | Ireland outage across `mongos`, CSRS and shard1; client validation |
| `SH-02` mongos regional locality | ✅ | local vs remote router latency, `w:1` and `w:"majority"` |
| `REC-01` Recover after majority loss | ✅ | 2+3 forced reconfiguration, plus proof of irreversibility |

Disaster recovery beyond normal MongoDB high availability is intentionally treated as a **design boundary rather than an evidence experiment** in this lab. Backup/restore and point-in-time recovery are relevant when HA cannot recover the database, but no unfinished DR scenario is represented in this evidence catalogue.

---

## Baseline configuration

The main replica set uses one member per region with London primary-preferred:

```javascript
{
  _id: 'psmdb-multiregion-lab',
  version: 2,
  members: [
    { _id: 0, host: 'psmdb-london:27017', priority: 3, tags: { region: 'london' } },
    { _id: 1, host: 'psmdb-ireland:27017', priority: 2, tags: { region: 'ireland' } },
    { _id: 2, host: 'psmdb-paris:27017', priority: 1, tags: { region: 'paris' } }
  ]
}
```

Members use region-readable hostnames through the lab's `/etc/hosts` alias layer.

### Observed priority takeover

An early assumption was that London would need a manual election after restarting as a SECONDARY. The evidence disproved that assumption: after catching up, MongoDB initiated a `priorityTakeover` and returned PRIMARY to the higher-priority London member.

**Finding:** priority is not only an initial-election preference; an eligible higher-priority member can later trigger a priority takeover.

Keeping this correction visible is useful: the evidence log records what the lab actually demonstrated rather than silently rewriting the original expectation.

---

## Baseline cross-region latency

Measured from the London PRIMARY through `rs.status()`:

| Link | Observed `pingMs` |
|---|---:|
| London → Ireland | 9–11 ms |
| London → Paris | 7–9 ms |

No synthetic `tc netem` delay was used for the evidence selected for the talk. The measured AWS inter-region latency was sufficient to expose the write-concern and read-routing trade-offs.

---

## `WC-01` — `w:1` vs `w:"majority"`

Method: `write_read_latency.py` from the London primary, 20 seconds per concurrency step. Running client and server on the same `t3.medium` is a known confound at high concurrency and should be stated when interpreting throughput.

### `w:"majority"`

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---:|---:|---:|---:|---:|---:|
| 10 | 536.4 | 18.2 | 21.63 | 25.47 | 0 |
| 25 | 1181.8 | 19.89 | 28.0 | 33.79 | 0 |
| 50 | 1579.8 | 28.32 | 48.41 | 63.75 | 0 |
| 100 | 1581.8 | 51.04 | 105.94 | 180.25 | 0 |

### `w:1`

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---:|---:|---:|---:|---:|---:|
| 10 | 2452.2 | 3.61 | 8.24 | 14.07 | 0 |
| 25 | 2342.4 | 9.26 | 21.89 | 36.87 | 0 |
| 50 | 2116.6 | 19.11 | 55.6 | 85.6 | 0 |
| 100 | 1825.5 | 37.13 | 149.96 | 298.44 | 0 |

### Findings

- At low concurrency, the measured p50 floor was ~3.6 ms for `w:1` versus ~18.2 ms for `w:"majority"`.
- The gap is consistent with the additional cross-region acknowledgement path in this topology.
- `w:"majority"` throughput plateaued around concurrency 50 on the test instance while latency continued rising.
- `w:1` throughput declining at higher concurrency is partly confounded by the benchmark client sharing the same 2-vCPU host as `mongod`; do not present that behaviour as a general MongoDB rule.
- All recorded runs completed with zero benchmark errors.

**Talk-safe conclusion:** stronger acknowledgement across geography has a real latency cost; measure it in the topology you intend to operate.

---

## `READ-01` — Read preference

Same benchmark harness, London primary.

| mode | concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|---:|
| primary | 10 | 2796.7 | 2.88 | 8.26 | 11.61 |
| primary | 25 | 2642.5 | 7.19 | 22.35 | 32.17 |
| primary | 50 | 2324.3 | 15.77 | 55.66 | 81.58 |
| primary | 100 | 1865.0 | 27.14 | 170.24 | 286.58 |
| primaryPreferred | 10 | 2803.1 | 2.88 | 8.26 | 11.82 |
| primaryPreferred | 25 | 2668.2 | 7.06 | 22.15 | 32.0 |
| primaryPreferred | 50 | 2378.7 | 15.63 | 52.49 | 79.06 |
| primaryPreferred | 100 | 1888.1 | 27.33 | 163.16 | 285.83 |
| secondaryPreferred | 10 | 960.1 | 9.83 | 12.33 | 12.88 |
| secondaryPreferred | 25 | 2377.8 | 9.76 | 12.64 | 13.65 |
| secondaryPreferred | 50 | 3038.6 | 14.45 | 26.31 | 36.32 |
| secondaryPreferred | 100 | 2482.2 | 27.4 | 94.58 | 150.21 |

### Findings

- `primary` and `primaryPreferred` were nearly identical while the primary was healthy.
- `secondaryPreferred` introduced a cross-region latency floor at low concurrency.
- At concurrency 50, secondaryPreferred produced higher throughput in this lab, consistent with reads being moved away from the host also running the client workload.
- The concurrency-10 `secondaryPreferred` result (960.1 ops/sec) does not follow the otherwise clean pattern and remains an unconfirmed startup/topology-discovery artefact. Do not cite it as a general finding without rerunning it.

---

## `RS-01` — Primary failure, election and recovery

Raw captures are in `docs/evidence-raw/`.

### Graceful primary stop

| Time (UTC) | Event |
|---|---|
| 2026-08-16 14:43:54 | Baseline: London PRIMARY; Ireland ~11 ms; Paris ~8 ms |
| 14:48:23 | `systemctl stop mongod` issued on London |
| 14:48:23.953 | Election started: `Starting an election due to step up request` |
| 14:48:23.975 | Ireland won the election |
| 14:48:24.003 | Ireland writable as PRIMARY |
| 14:58:38 | London restarted |
| 14:58:50.383 | London reclaimed PRIMARY through priority takeover |
| 14:59:30 | Recovery check: secondaries caught up (`replLag: 0 secs`) |

The recorded graceful handover reached a writable replacement primary in roughly **50 ms once the election was triggered**.

### Ungraceful primary failure

London was killed with:

```bash
systemctl kill -s SIGKILL mongod
```

| Time (UTC) | Event |
|---|---|
| 15:13:55 | SIGKILL sent |
| 15:14:06.131 | Election started after no PRIMARY was seen for the election timeout period |
| 15:14:06.174 | Election succeeded |
| 15:14:06.222 | New primary writable |

**Key distinction:** kill-to-election-start was ~11.1 s, while election-start-to-writable was ~91 ms. The dominant difference between the graceful and abrupt tests was **failure detection time**, not a slow election protocol.

London's restart also recorded `Startup from clean shutdown?: false` and WiredTiger recovery before it rejoined.

### Recovery and data observation

London later reclaimed PRIMARY via priority takeover. Both secondaries showed `replLag: 0 secs` at the recorded recovery check. No acknowledged `w:"majority"` data loss was observed in these tests.

**Caveat:** these failover timings came from an idle lab. Use them to explain the mechanism and the measured run, not as an SLA prediction for a production workload.

---

## `RS-03` — Even-vote 2+2 topology

Topology: London x2 + Ireland x2, four voting data-bearing members.

When both members in one region were stopped, the surviving side had 2/4 votes. The evidence showed the primary stepping down/no writable primary being available, client writes failing with `NotWritablePrimary`, and repeated election refusal because a majority could not be seen.

**Finding:** an even number of voters is not itself the root principle; the problem is that the tested failure left neither side with the required majority.

---

## `RS-05` — Arbiter and election majority

An arbiter was added to the 2+2 data-bearing topology, creating five votes.

The important result is narrower than "arbiter fixes the cluster":

- the arbiter contributes an **election vote**,
- it does **not** store another copy of the data,
- therefore election availability and data-bearing write acknowledgement must be reasoned about separately.

The recorded `w:1` / `w:"majority"` test under the relevant outage is kept as evidence of that distinction.

**Preferred terminology:** "add an arbiter to restore election majority," not "arbiter fix."

---

## `RS-04` — Region-majority anti-pattern

Topology: London x2 + Ireland x3.

This topology has five votes, but Ireland contains three of them. Removing Ireland therefore removes the replica-set majority even though London still has two healthy data-bearing members.

**Finding:** "use an odd number of members" is incomplete guidance. What matters is **where the majority survives under the failure model you intend to tolerate**.

---

## `LAT-01` — Multi-AZ comparison

The lab also contains a three-member replica set within London for same-region comparison. Its purpose is to make the geography trade-off measurable using the same benchmark methodology rather than comparing unrelated systems.

Use the raw/recorded Multi-AZ results when quoting exact values; the durable conclusion for the talk is that failure-domain distance affects acknowledgement and routing latency, so HA topology and performance requirements must be designed together.

---

## `SH-01` — Sharded-cluster regional outage

The sharded cluster contains:

- a three-member CSRS spread across London/Ireland/Paris,
- shard1 as a three-member replica set spread across the same regions,
- one `mongos` router per region.

The regional-outage test stopped the Ireland `mongos`, Ireland CSRS member and Ireland shard1 member together. The surviving CSRS and shard replica set retained majority, and the client used a multi-`mongos` seed list from London.

The recorded benchmark completed with **zero client errors** during the tested outage.

**Talk-safe conclusion:** the regional failure was survived because the required MongoDB layers retained their own availability conditions and the client had a surviving routing path — not simply because the deployment was labelled "multi-region."

**Build note:** shard1's initial bootstrap addressed members by private IP rather than hostname (a normalization step that was missed for this one component). `sh.addShard()` surfaced the mismatch directly, with the seed list's hostnames not matching the replica set's own reported IP-based config — fixed with the same `rs.reconfig()` hostname-normalization pattern used elsewhere in the build (see runbook A6). Worth keeping as an example of the cluster catching its own misconfiguration rather than failing silently.

---

## `SH-02` — mongos regional locality

**Question:** does it matter which region's `mongos` an application talks to, given that a router itself holds no data?

Method: benchmark client colocated on London's `mongos` host, targeting `localhost:27017` (local router) versus `psmdb-mongos-ireland:27017` (a deliberately remote router) — same client location both times, isolating router choice as the only variable. `shard1`'s primary was in London for this test.

### `w:1`

| target | concurrency | ops/sec | p50 ms |
|---|---:|---:|---:|
| local | 10 | 2605.7 | 3.36 |
| local | 25 | 2508.9 | 8.53 |
| local | 50 | 2107.3 | 18.65 |
| remote | 10 | 415.9 | 23.24 |
| remote | 25 | 1052.7 | 23.12 |
| remote | 50 | 2084.8 | 23.07 |

### `w:"majority"`

| target | concurrency | ops/sec | p50 ms |
|---|---:|---:|---:|
| local | 10 | 462.6 | 20.57 |
| local | 25 | 1161.1 | 20.77 |
| local | 50 | 1908.6 | 24.61 |
| remote | 10 | 217.9 | 44.88 |
| remote | 25 | 553.8 | 44.36 |
| remote | 50 | 1081.3 | 44.15 |

### Findings

- Remote-router latency floor was roughly double the local-router floor in both write-concern modes — consistent with paying the cross-region network hop twice: client→remote router, then router→shard primary.
- Remote latency stayed essentially flat across concurrency 10–50; local latency rose with load. At this scale the fixed double-hop network cost dominated over any local queueing effect.
- `w:"majority"` added a broadly similar offset to both local and remote floors (shard1's own replication-wait cost), which did not change the local-vs-remote relationship — that cost is shard-internal, not router-related.

**Talk-safe conclusion:** a `mongos` router's location is not incidental. An application talking to a nearby router avoids paying network cost twice; this is a real, measurable design consideration for regional application placement, not just a topology diagram detail.

---

## `REC-01` — Recover after majority loss

Topology: **London x2 + Ireland x3** (5 votes, 3 held by Ireland), built as a dedicated scoped rebuild rather than extending the main baseline cluster (see runbook Appendix for why, and the Terraform limitation that shaped that decision).

**This scenario is deliberately different from every other outage test in this log.** `RS-01`, `RS-03`, `RS-04` and `SH-01` are all reversible — stopped nodes always came back and the cluster self-healed. `REC-01` demonstrates MongoDB's documented recovery procedure (`rs.reconfig(cfg, { force: true })`) for when a majority is lost **permanently**, not just temporarily.

**Baseline** (2026-08-23, ~17:17 UTC): all 5 members healthy, London PRIMARY.

**Outage** — all 3 Ireland members stopped simultaneously, 17:19:28 UTC. Same lockout signature as `RS-04`: London's 2 votes cannot reach the 3-vote majority of the *existing* 5-member config; no writable primary.

**Forced recovery** — run directly on a surviving member, declaring a new, smaller config consisting only of the survivors:

```javascript
cfg = rs.conf()
cfg.members = cfg.members.filter(m => ["psmdb-london:27017", "psmdb-london-2:27017"].includes(m.host))
cfg.version += 1
rs.reconfig(cfg, { force: true })
```

**Result:** new majority correctly recognized (`majorityVoteCount: 2, votingMembersCount: 2` — not 3-of-5), a primary elected among the two survivors (`electionTimeout`, term 2), and a `w:"majority"` write succeeded immediately afterward (`replLag: 0 secs` between the two survivors).

**The critical follow-up — proving this is genuinely irreversible.** The stopped Ireland member was restarted (data intact, process healthy) and connected to directly:

```javascript
rs.status()
// MongoServerError[InvalidReplicaSetConfig]: Our replica set config is invalid or we are not a member of it
```

Ireland is running, has its data, and is **permanently excluded** — it still holds the old 5-member config, which no longer exists from the survivors' perspective. There is no automatic path back in.

**Findings:**

- `force: true` correctly recomputes majority against the *new*, smaller member list, not the old one.
- The excluded member does not silently rejoin or cause conflict on its own — it is simply locked out, reporting an explicit, unambiguous error.
- This is the tool's real safety property: a returning node that still believes in the old config cannot force its way back in and cause disagreement by itself.

**Talk-safe conclusion:** `force: true` is correct only when the missing majority is genuinely, permanently gone — a confirmed disaster, not a network blip expected to heal. If it is used prematurely against a majority that later turns out to be only temporarily unreachable, the returning nodes and the forcibly reconfigured survivors can end up holding two different, conflicting versions of the replica set's history — genuine split-brain, not just an inconvenience like the lockout demonstrated here. This is disaster recovery for confirmed disasters, not a routine outage response.

---

## Evidence interpretation rules

These rules keep the repository useful after the talk:

1. **Measured is not universal.** Keep exact timings tied to the environment/run that produced them.
2. **Mechanism before number.** Explain why the state changed before emphasizing milliseconds.
3. **Keep corrections.** If testing disproves an assumption, record the correction rather than rewriting history.
4. **Separate election from durability.** A voting majority and a data acknowledgement are related but not identical concepts.
5. **Capture recovery.** A resilience test is incomplete if it only records the failure and not the return to steady state.
6. **Raw evidence wins.** Slides summarize; this log interprets; `evidence-raw/` is the underlying proof.
