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
| 3 — Write concern + read preference benchmarks | ✅ Done | 22–25 |
| 4 — Arbiter, primary failure, regional outage, recovery | ✅ Done — graceful/ungraceful failover, even-vote & region-majority anti-patterns, arbiter fix, write-concern-vs-election-majority nuance | 16–19, 26, 30–32 |
| 4b — Multi-AZ comparison topology (bonus, not originally scoped) | ✅ Done — write concern + read preference benchmarks, direct latency decomposition vs multi-region | 8, 10 |
| 5 — Sharded cluster (CSRS + shard(s) + mongos) | ⬜ Not started | 34–37 |
| 6 — Full evidence pass + rehearsal | ⬜ Not started | — |

---

## 1. Replica set configuration (slides 13, 14, 21)

`rs.conf()` — London primary-preferred (priority 3), region tags on every member.
Members are addressed by region-named hostname (`psmdb-london` etc.), not raw
IP — resolved via an `/etc/hosts` alias layer templated by the `common`
Ansible role, so this stays readable even if the underlying private IPs
ever change on a rebuild:

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

**Correction to an earlier assumption, worth keeping visible rather than
quietly fixing:** During testing, London's `mongod` was restarted (as a
side effect of an unrelated Ansible config change) and rejoined the set
as SECONDARY, as expected. It was initially assumed this would require
a manual/forced election to reclaim PRIMARY. That was wrong —
`rs.status().electionCandidateMetrics.lastElectionReason` showed
`'priorityTakeover'`: once London had fully caught up, MongoDB
automatically triggered an election to hand PRIMARY back to it, purely
because of its higher configured priority. **Priority isn't just a tiebreaker
at initial election — it's actively enforced on an ongoing basis.** Good,
accurate, slightly more interesting evidence for slide 21 than originally
planned — the correction is more useful than the original assumption
would have been.

## 2. Baseline cross-region latency (slides 15, 24)

Measured via `rs.status().members.forEach(m => print(m.name, m.stateStr, m.pingMs))`
from London (PRIMARY):

| Link | pingMs |
|---|---|
| London → Ireland | 9–11ms (measured at two different points; normal variance) |
| London → Paris | 7–9ms (measured at two different points; normal variance) |

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

## 6. Primary failure, election & recovery (slides 16–17, 30–32)

Full raw captures live in `docs/evidence-raw/` (see that directory's
README for the naming convention).

| Time (UTC) | Event | Detail |
|---|---|---|
| 2026-08-16 14:43:54 | Baseline captured | London PRIMARY, Ireland pingMs=11, Paris pingMs=8. `docs/evidence-raw/rs-status-before-primary-failure-20260816.txt` |
| 2026-08-16 14:48:23 → 14:48:39 | mongod stopped on London | Graceful `systemctl stop`, 16s shutdown duration |
| 2026-08-16 14:48:23.953 | Election started | `"Starting an election due to step up request"` — triggered by London's own graceful-shutdown signal, not a heartbeat timeout |
| 2026-08-16 14:48:23.975 | Election won | Paris voted yes (term 18); London unreachable (`ShutdownInProgress` — still mid-shutdown when the vote request arrived) |
| 2026-08-16 14:48:24.003 | Ireland writable as PRIMARY | `"Transition to primary complete; database writes are now permitted"`. Full log: `docs/evidence-raw/election-log-ireland-becomes-primary-20260816.txt` |
| 2026-08-16 14:58:38 | London restarted | `systemctl start mongod` |
| 2026-08-16 14:58:50.383 | London reclaimed PRIMARY | Automatic priority takeover, ~12.4s after restart |
| 2026-08-16 14:59:30 | Recovery confirmed | Both Ireland and Paris showing `replLag: 0 secs` — fully caught up |

**Two distinct RTO numbers, worth presenting separately rather than
averaged into one — they answer different questions:**

- **Failover RTO (failure → new primary): ~50ms (graceful) vs ~11.1s (ungraceful).**
  Both tested — see the ungraceful breakdown below, which reveals *why*
  the gap is so large.
- **Reclaim RTO (restart → priority takeover): ~12.4s.** Time for
  London to restart, rejoin as secondary, catch up on the oplog, and
  trigger an automatic priority-takeover election once eligible.

### Ungraceful failure test (2026-08-16, ~15:13-15:14 UTC)

Same scenario, hard kill instead of graceful stop —
`systemctl kill -s SIGKILL mongod` on London while it was PRIMARY.

| Time (UTC) | Event |
|---|---|
| 15:13:55 | `SIGKILL` sent — `systemctl status` confirms `Result: signal`, `code=killed, signal=KILL` |
| 15:14:06.131 | Election starts — log: `"Starting an election, since we've seen no PRIMARY in election timeout period"`, `electionTimeoutPeriodMillis: 10000` |
| 15:14:06.144 | Dry-run vote to London fails with `HostUnreachable` / `Connection refused` — genuinely unreachable, not a clean shutdown response this time |
| 15:14:06.174 | `"Election succeeded, assuming primary role"` (term 20) |
| 15:14:06.222 | `"Transition to primary complete; database writes are now permitted"` |

**The breakdown that matters:** kill-to-election-start took **~11.1s**
(bounded by the 10s `electionTimeoutMillis`, plus ~1s of heartbeat
interval before the timeout timer could even start counting). But
election-start-to-writable took only **~91ms** — nearly the same order
of magnitude as the graceful case's ~50ms. **The election protocol itself is fast regardless of trigger; almost the entire RTO gap between
graceful and ungraceful failure is detection time, not election time.**
This is a more precise and more defensible claim for the talk than
"hard failures are ~200x slower" — the real story is "the cluster is
always fast to elect once it knows there's a problem; the variable is
how fast it finds out."

**Unclean-shutdown recovery on restart (bonus evidence for slide 30-32):**
London's own log explicitly confirms this wasn't a clean restart:
`"Startup from clean shutdown?": false`, and
`"Incrementing the rollback ID after unclean shutdown"`. WiredTiger
recovery took **215ms** (196ms log replay + 1ms rollback-to-stable +
17ms checkpoint) — a step the graceful restart skipped entirely, since
there was nothing to recover from. This 215ms was small only because
the cluster was idle at the moment of the crash (1 op to replay); under
real write load this recovery step would scale with how much unflushed
data existed at the crash moment — another concrete instance of the
"idle lab vs production load" caveat above, not just an assertion.

**Final state confirmed:** London reclaimed PRIMARY again via automatic
priority takeover (third time this behavior has been observed in this
session — consistent, not a one-off). Both secondaries healthy,
`health: 1` across all three members.

**RPO: zero data loss confirmed.** Both secondaries showed
`replLag: 0 secs` by the time recovery was checked — nothing
acknowledged under `w:"majority"` was lost across either transition.

**Caveat worth stating explicitly on the slide, not just here:** these
specific numbers were measured on an **idle** lab cluster — no write
load running during either transition. That matters differently for
each part of the timing:

- **The mechanism is load-independent and generalizes.** Graceful
  shutdown triggering a near-instant handover (rather than waiting out
  the heartbeat timeout) is a property of how MongoDB's replication
  protocol works, not an artifact of this lab being idle. Same for the
  priority-takeover behavior. Safe to present as a general finding.
- **The specific durations are not production-representative and
  should be labeled as such.** Under real write load: (1) graceful
  shutdown itself would likely take longer than 16s — more dirty
  WiredTiger pages to flush before a clean stop completes; (2) the
  ~12.4s reclaim time included almost zero actual catch-up, since
  nothing was writing while London was down — in production, London
  would have a real oplog gap to replay first, scaling with both
  outage duration and write rate during it; (3) the ~50ms
  election-to-writable window is mostly CPU/network-bound rather than
  data-volume-bound, so it likely generalizes better than the other
  two numbers, but hasn't been tested under load to confirm.

**Recommended framing for the talk:** present the mechanism as the
finding, caveat the specific numbers as idle-cluster measurements.
Don't imply these durations would hold in production — that's the
kind of claim a technical audience will correctly push back on in Q&A.

## 7. 2+2+1 topology: even-vote-count anti-pattern & partition demo (slides 8, 10, 19, 26)

### Build

Standalone arbiter instance (deliberate design choice, not co-located
on an existing node — see rationale below): `t3.micro`, Paris region,
hostname `psmdb-paris-arbiter` (`13.36.233.135` / `10.30.2.96`).

Two new data-bearing nodes added via the same `ec2-fleet` Terraform
module, second AZ per region for genuine within-region multi-AZ spread:
- `psmdb-london-2` — `18.134.210.137` / `10.10.2.153`
- `psmdb-ireland-2` — `108.129.131.192` / `10.20.2.217`

**Why the arbiter is a standalone EC2 instance, not co-located:**
initially built co-located (second `mongod` process, port 27020, on
the existing Paris node) — this worked technically but was reconsidered
for talk clarity. A standalone instance means `rs.conf()` shows a clean
`psmdb-arbiter:27017` alongside the other hostnames rather than two
processes sharing one box on different ports, which needs an extra
sentence of explanation mid-talk. Cost difference is negligible
(~$0.01/hr for a `t3.micro`). Also technically simpler to build: an
arbiter is *just a regular mongod process* — there's no special
"arbiter mode" in `mongod.conf`, arbiter status is purely a
replica-set-config-level distinction (`rs.addArb()`). A dedicated
instance reuses the standard `psmdb` Ansible role completely unchanged
— no custom systemd unit, no non-standard port, none of the PID-file
debugging the earlier co-located attempt required.

`rs.add()` sequence — both joined healthy, priorities matching their
region-mate: `psmdb-london-2` priority 3, `psmdb-ireland-2` priority 2.

### The anti-pattern: even vote count

`rs.remove("psmdb-paris:27017")` — Paris's original data-bearing
member removed, leaving **4 voting data-bearing members**: London,
London-2 (both region A), Ireland, Ireland-2 (both region B). No
arbiter added yet at this point — deliberately sequenced to demonstrate
the problem before the fix.

```
_id 0: psmdb-london:27017    priority 3  votes 1
_id 1: psmdb-ireland:27017   priority 2  votes 1
_id 3: psmdb-london-2:27017  priority 3  votes 1
_id 4: psmdb-ireland-2:27017 priority 2  votes 1
```

**Known gap, not yet resolved:** `psmdb-london-2` and `psmdb-ireland-2`
show `tags: {}` in `rs.conf()`, unlike the original members which carry
`tags: { region: '...' }`. A fix was proposed (manual `rs.reconfig()`
setting the tags) but not confirmed applied — check before relying on
region-tagged `secondaryPreferred` reads against this topology.

### Live partition demonstration

Simulated a London↔Ireland network partition by stopping both Ireland
nodes (outcome on vote math is identical to a real TGW link failure
between the regions — London's side simply can't reach Ireland's votes
either way).

| Time (UTC) | Event |
|---|---|
| 18:55:03 | `psmdb-ireland` mongod stopped |
| 18:57:06 | `psmdb-ireland-2` mongod stopped |
| (shortly after) | London **stepped down from PRIMARY to SECONDARY** — with only 2 of 4 votes reachable (itself + London-2), can't maintain the 3-vote majority required |

**Direct proof of write-unavailability** — attempted a real write from
London while partitioned:
```javascript
db.getSiblingDB("benchmark").latency_test.insertOne({test: "partition-demo", ts: new Date()})
// MongoServerError[NotWritablePrimary]: not primary
```
A completely healthy 4-node cluster — every machine up and running —
refusing every write. Not a crash, not a bug: the direct, correct
consequence of an even vote count meeting a network split.

**Repeated, explicit refusal in the logs** — over ~4 minutes
(18:57:43 → 19:01:07), London retried an election roughly every 10-11s
and correctly refused every single time, identical reason each time:
```
"Not starting an election, since we are not electable"
reason: "Not standing for election because I cannot see a majority (mask 0x1)"
```
This is stronger evidence than a single log line — it shows the
cluster's split-brain protection actively working, repeatedly, not
just quietly giving up once. Full capture:
`docs/evidence-raw/partition-demo-log-london-20260816.txt`

### Recovery

Both Ireland nodes restarted, cluster recovered cleanly: London
SECONDARY, Ireland SECONDARY, **London-2 PRIMARY**, Ireland-2 SECONDARY.

**Secondary finding worth noting:** London-2 won the post-recovery
election, not London, despite both being configured at priority 3.
Tied priority has no fixed tiebreaker — either can legitimately win.
Not a bug, but worth knowing if a fully deterministic "always this
specific node becomes primary" story is wanted for a slide; would need
to break the tie (e.g. 3 vs 2.5) rather than leave them equal.

### The fix: arbiter added

`rs.addArb("psmdb-paris-arbiter:27017")` — joined cleanly. `rs.status()`
shows a genuinely distinct `ARBITER` state (not PRIMARY/SECONDARY),
`rs.conf()` confirms `arbiterOnly: true`, `priority: 0`, `votes: 1`.
**5 total votes, majority 3, odd — fixed.**

Bonus: the empty-tags gap flagged above is now resolved — London-2 and
Ireland-2 both correctly show `tags: { region: '...' }` in this
snapshot. Full config: `docs/evidence-raw/rs-conf-topology-snapshots-20260816.txt` (stage 3).

**Next:** repeat the identical partition test (stop both Ireland nodes)
against this 5-vote config and confirm London's side (London +
London-2 + arbiter = 3 votes) stays writable this time — direct
before/after contrast against the Stage 2 failure above.

### Critical nuance found live: the arbiter fixes election, not write availability

Ran the partition test again against the fixed 5-vote config — stopped
`psmdb-ireland` and `psmdb-ireland-2` a second time. Election worked as
predicted: `psmdb-london-2` became PRIMARY (3-of-5 votes reachable —
London, London-2, arbiter — comfortably majority for election).

**But a plain write attempt still stalled**, and investigating why
surfaced a genuinely important distinction MongoDB draws that's easy
to conflate: **election majority and write-concern majority are
counted differently.**

`rs.status()` during the partition, showing exactly which nodes were
unreachable at the moment of the write attempt:

```
psmdb-london:27017         SECONDARY            health=1
psmdb-ireland:27017         (not reachable/healthy)  health=0
psmdb-london-2:27017       PRIMARY              health=1
psmdb-ireland-2:27017       (not reachable/healthy)  health=0
psmdb-paris-arbiter:27017  ARBITER              health=1
```

- **Election majority counts votes.** The arbiter has a vote. 3-of-5
  reachable → election succeeds. This is what the arbiter actually
  fixes.
- **`w:"majority"` write-concern counts data-bearing acknowledgments
  only.** The arbiter holds no data, so it can never acknowledge a
  write — it doesn't count toward this number *at all*. There are 4
  data-bearing voting members (London, Ireland, London-2, Ireland-2);
  majority of *those* is 3. With Ireland's pair down, only 2 are
  reachable. **Majority writes can never succeed while partitioned,
  regardless of the arbiter.**

Confirmed directly:

```javascript
// w:1 — only needs the primary's own ack. Succeeds instantly.
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "post-arbiter-fix-w1", ts: new Date()},
  {writeConcern: {w: 1}}
)
// { acknowledged: true, insertedId: ObjectId('6a8210e5d07e7a8504c421c1') }

// w:"majority" — times out. Needs 3-of-4 data-bearing acks, only 2 reachable.
db.getSiblingDB("benchmark").latency_test.insertOne(
  {test: "post-arbiter-fix-wmajority", ts: new Date()},
  {writeConcern: {w: "majority", wtimeout: 5000}}
)
// MongoWriteConcernError[WriteConcernFailed]: waiting for replication timed out
// n: 1, writeConcernError: { code: 64, errmsg: 'waiting for replication timed out' }
```

**Worth being precise about `n: 1` in that error** — the write *did*
apply locally on the primary. It's not that the write failed outright;
it's that the write concern (the durability guarantee the client asked
for) couldn't be satisfied in time. A client using `w:1` would never
know anything was wrong; a client requiring `w:"majority"` correctly
gets told its durability guarantee wasn't met.

**This is the single most important nuance for slide 26**, arguably
more valuable than the vote-count fix itself: *adding an arbiter
restores your ability to elect a leader during a partition, but it
does not restore full write durability* — that still requires enough
data-bearing nodes to be reachable, arbiter or not. An audience member
who only remembers "add an arbiter, problem solved" would be wrong in
a way that matters in production. Found live, not planned — a better
result than if this had been scripted in advance.

## 8. Region-majority anti-pattern: odd total votes is necessary but not sufficient (slides 8, 10, 19, 26)

Direct follow-up to section 7's even-vote-count demo — same failure
signature (`NotWritablePrimary`, repeated "cannot see a majority"
refusals), different root cause. Point: **an odd total vote count
alone doesn't guarantee safety if one region holds a majority by
itself.**

### Setup

Removed the Paris arbiter from the replica set (`rs.remove`), stopped
its process, added a third Ireland node instead (`psmdb-ireland-3`,
same `ec2-fleet` Terraform pattern, priority 1, region-tagged).

**Before:**
```
psmdb-london:27017    SECONDARY  health=1
psmdb-ireland:27017   SECONDARY  health=1
psmdb-london-2:27017  PRIMARY    health=1
psmdb-ireland-2:27017 SECONDARY  health=1
```
(London = 2 votes, Ireland = 2 votes — pre-addition baseline)

`rs.add({ host: "psmdb-ireland-3:27017", priority: 1, tags: { region: "ireland" } })`

**After** — the target anti-pattern topology, `rs.conf()` version 12,
term 33 (full config: `docs/evidence-raw/rs-conf-topology-snapshots-20260816.txt`,
worth appending as a Stage 4 there too):
```
London:  psmdb-london (priority 3), psmdb-london-2 (priority 3)  = 2 votes
Ireland: psmdb-ireland (priority 2), psmdb-ireland-2 (priority 2),
         psmdb-ireland-3 (priority 1)                              = 3 votes
```
Total 5 votes, odd — passes the naive "odd is safe" rule. But Ireland
alone now holds outright majority (3-of-5).

### The demo — stop all of Ireland this time, not just half

| Time (UTC) | Event |
|---|---|
| 20:37:51 | `psmdb-ireland` mongod stopped |
| 20:38:15 | `psmdb-ireland-2` mongod stopped |
| 20:38:36 | `psmdb-ireland-3` mongod stopped |

`rs.status()` immediately after:
```
psmdb-london:27017     SECONDARY               health=1
psmdb-ireland:27017    (not reachable/healthy)  health=0
psmdb-london-2:27017   SECONDARY               health=1
psmdb-ireland-2:27017  (not reachable/healthy)  health=0
psmdb-ireland-3:27017  (not reachable/healthy)  health=0
```

Write attempt:
```javascript
db.getSiblingDB("benchmark").latency_test.insertOne({test: "region-majority-antipattern", ts: new Date()})
// MongoServerError[NotWritablePrimary]: not primary
```

Log confirms the same repeated, correct refusal pattern as section 7
(full capture: `docs/evidence-raw/region-majority-antipattern-log-20260816.txt`):
```
"Not starting an election, since we are not electable"
reason: "Not standing for election because I cannot see a majority (mask 0x1)"
```
Repeated every ~10-11s starting 20:39:02, continuing past 20:39:46.

### The actual lesson

Section 6 proved: even total vote count → a split can produce two
groups that are both stuck. This section proves the complementary
case: **odd total vote count is not sufficient on its own** — if any
single failure domain holds more than half the votes, that domain's
outage takes the whole cluster down with it, exactly like an even
split does, just via a different mechanism. The real safety property
isn't "is the total odd" — it's **"does any single failure domain
hold a majority by itself."** A genuinely safe topology needs both:
odd total, *and* no region concentrated above 50%. This 2+2+1 (with
the arbiter, not this 2+3 variant) satisfies both; 2+3 only satisfies
the first.

## Status summary — what's actually left

Everything in the original Phase 4 scenario catalogue is now **done**:
- ~~Arbiter toggle~~ ✅ done, plus the write-concern nuance
- ~~Regional outage~~ ✅ done twice (even-vote partition, region-majority) — more thorough than originally planned
- ~~Same outage, different topology~~ ✅ this is literally what sections 6 vs 7 are — same failure, two different topologies, directly comparable
- ~~Priority change~~ ✅ observed repeatedly and organically (the tied-priority nondeterminism finding across multiple elections) — not a dedicated scripted demo, but real evidence of priority behavior exists

**Genuinely remaining:**
- **Phase 5 — sharded cluster** (slides 34–37): config server replica
  set, shard replica set(s), `mongos` routers. Not started.
- *(Optional, not blocking)* A dedicated live priority-flip demo
  (set priority, force a specific election, show the intended primary
  win) — the *concept* is evidenced, but not as a clean standalone
  scripted moment. Worth doing only if slide 21 needs a cleaner visual
  than what already exists.

## 9. Multi-AZ vs multi-region: direct latency comparison (slides 8, 10)

Entirely separate replica set (`psmdb-multiaz-lab`), 3 nodes all within
London, spread across its 3 real AWS AZs (`eu-west-2a/b/c`) — this
required extending the VPC to a genuine third subnet, since the
original build only provisioned 2 AZs per region by default (fixed as
part of this addition). Independent of the main multi-region cluster;
same admin credentials reused, no new secrets needed.

`rs.conf()`:
```
{
  _id: 'psmdb-multiaz-lab',
  members: [
    { _id: 0, host: 'psmdb-multiaz-1:27017' },  // eu-west-2a
    { _id: 1, host: 'psmdb-multiaz-2:27017' },  // eu-west-2b
    { _id: 2, host: 'psmdb-multiaz-3:27017' }   // eu-west-2c
  ]
}
```

**Measured cross-AZ latency** (`rs.status().members[].pingMs`):

| Link | pingMs |
|---|---|
| multiaz-1 → multiaz-2 | 0 (sub-millisecond) |
| multiaz-1 → multiaz-3 | 0 (sub-millisecond) |

**Direct comparison against the multi-region baseline** (section 2):

| Topology | Measured latency |
|---|---|
| Multi-region (London↔Ireland↔Paris) | 7–11ms |
| Multi-AZ (single region, 3 AZs) | <1ms |

Roughly a **10-20x difference** — real, measured evidence for exactly
the "order of magnitude" estimate discussed early in this build,
now backed by numbers instead of general AWS-published figures. This
is the concrete trade-off slide 8/10 makes: multi-AZ protects against
rack/power/network failure within a region at near-zero latency cost;
multi-region protects against a whole-region outage, at a real,
measurable latency cost.

**Write-concern benchmark, run against this topology** — same
methodology and concurrency ramp as section 3, run from `psmdb-multiaz-1`:

### w:"majority"

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---|---|---|---|---|---|
| 10 | 1060.8 | 8.65 | 14.39 | 20.3 | 0 |
| 25 | 1186.3 | 15.38 | 46.4 | 134.43 | 0 |
| 50 | 1483.5 | 27.88 | 61.91 | 96.31 | 0 |
| 100 | 1425.2 | 53.79 | 136.3 | 242.92 | 0 |

### w:1

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms | errors |
|---|---|---|---|---|---|
| 10 | 2357.2 | 3.79 | 8.03 | 13.53 | 0 |
| 25 | 2105.6 | 9.71 | 27.07 | 42.15 | 0 |
| 50 | 1655.4 | 21.39 | 74.19 | 153.04 | 0 |
| 100 | 1638.0 | 36.41 | 183.34 | 333.3 | 0 |

**Three findings from the direct comparison against section 3's
multi-region numbers:**

1. **The majority-write floor cleanly decomposes into local commit
   overhead + network RTT.** At low concurrency, multi-AZ's `w:"majority"`
   p50 is **8.65ms**, multi-region's is **18.2ms**. The gap (≈9.5ms)
   lines up almost exactly with the measured cross-region RTT (9-11ms,
   section 2) — and multi-AZ's 8.65ms floor is very close to what
   multi-region's floor would be *minus* that RTT. In other words:
   `majority-write latency ≈ local durability overhead (~8-9ms,
   present in both topologies) + network RTT to the needed secondary
   (~0ms multi-AZ, ~9-11ms multi-region)`. The "local overhead" — likely
   WiredTiger journal commit and driver/server processing — exists
   regardless of topology; only the network component changes.

2. **At high concurrency, the two topologies converge.** By
   concurrency 100, multi-AZ (53.79ms p50, 1425 ops/sec) and
   multi-region (51.04ms p50, 1582 ops/sec, section 3) look similar —
   both hitting the same `t3.medium` capacity ceiling. **Multi-AZ's
   latency advantage matters most when the system isn't saturated** —
   under heavy load, instance capacity becomes the bottleneck
   regardless of network topology. Don't oversell multi-AZ as
   unlimited extra throughput headroom; it buys lower latency at a
   given load, not a higher ceiling.

3. **`w:1` latency is topology-independent — striking confirmation.**
   Multi-AZ and multi-region `w:1` numbers are nearly identical at
   every concurrency level (e.g. p50 at 10: 3.79ms vs 3.61ms; at 100:
   36.41ms vs 37.13ms). This makes complete sense once stated: `w:1`
   only waits on the primary's own local acknowledgment, never any
   secondary — so it can't be affected by cross-AZ vs cross-region
   network distance at all. **Only `w:"majority"` is topology-sensitive**,
   because only it waits on replication. Clean, well-evidenced
   distinction for the talk.

**Read preference comparison, same topology:**

### primary

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 2425.3 | 3.31 | 9.66 | 13.75 |
| 25 | 2046.8 | 8.86 | 29.81 | 60.12 |
| 50 | 2103.6 | 16.98 | 61.73 | 93.33 |
| 100 | 1676.0 | 30.81 | 188.14 | 320.06 |

### primaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 2367.2 | 3.4 | 9.79 | 14.38 |
| 25 | 2065.3 | 9.04 | 29.98 | 51.48 |
| 50 | 2093.8 | 17.09 | 60.82 | 92.59 |
| 100 | 1619.4 | 31.44 | 197.29 | 331.73 |

### secondaryPreferred

| concurrency | ops/sec | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| 10 | 3161.4 | 2.58 | 6.69 | 9.68 |
| 25 | 2961.2 | 6.23 | 20.76 | 30.96 |
| 50 | 2122.3 | 15.39 | 59.66 | 170.94 |
| 100 | 2265.3 | 25.78 | 130.92 | 220.8 |

**Two more findings, both confirming patterns already seen elsewhere
in this build:**

4. **`primary` reads are topology-independent, matching the `w:1`
   finding for writes.** Multi-AZ `primary` p50s (3.31–30.81ms across
   the ramp) track closely with multi-region's (2.88–27.14ms, section 4)
   — small differences are ordinary instance-level variance, not a
   topology effect. Makes sense: a `primary` read never leaves the
   primary node, so cross-AZ vs cross-region distance simply doesn't
   enter into it.

5. **`secondaryPreferred` shows the same latency-decomposition pattern
   as the write-concern test.** At concurrency 10, multi-AZ's
   `secondaryPreferred` p50 is **2.58ms** vs multi-region's **9.83ms**
   (section 4) — the gap tracks the measured cross-region RTT almost
   exactly, same as finding #1 above for majority writes. Also: within
   this topology, `secondaryPreferred` (2.58ms) actually **beats**
   `primary` (3.31ms) at the same concurrency — the same
   CPU-contention effect first observed in section 4 (client benchmark
   and the node it's reading from share the same 2 vCPUs; offloading
   to a different node than the primary relieves that contention).
   That this effect shows up again, in a second topology, is good
   evidence it's a real, general finding — not a one-off artifact of
   the original test setup.

## 10. Sharded cluster build (slides 34–37)

**Scope, deliberately trimmed:** CSRS (3 nodes, 1 per region) + 1 shard
replica set (3 nodes, 1 per region) + 3 `mongos` routers (1 per
region). Shard count doesn't matter for the actual thing being tested
here — `mongos` regional placement and routing behavior — so a second
shard was skipped as unnecessary scope for this build.

**Real bug hit and fixed:** the `shard1` bootstrap template addressed
members by raw private IP instead of `psmdb_alias`, missed when
carrying over the hostname-switch pattern already established for the
main cluster and `multiaz`. `sh.addShard()` failed on first attempt
with a clear error naming the mismatch; fixed via the same manual
`rs.reconfig()` pattern used twice before.

**Confirmed working end to end** — `sh.status()` after registering
the shard:
```
shards: [{ _id: 'psmdb-shard1', host: 'psmdb-shard1/psmdb-shard1-ireland:27017,psmdb-shard1-london:27017,psmdb-shard1-paris:27017', state: 1 }]
active mongoses: [{ '7.0.39-21': 3 }]
```
One shard registered, all 3 `mongos` routers actively connected to the
cluster.

## 11. mongos regional locality: does it matter which router you use? (slides 34-37)

**Test design:** benchmark client colocated on London's `mongos` box,
deliberately targeting local (`localhost:27017`) vs a remote router
(`psmdb-mongos-ireland:27017`) — same client location, only the router
target changes, isolating the "does mongos choice matter" variable.
`shard1`'s primary is in London for this test.

### w:1 (isolates routing/connection cost)

| Target | concurrency | ops/sec | p50 ms |
|---|---|---|---|
| Local (London) | 10 | 2605.7 | 3.36 |
| Local (London) | 25 | 2508.9 | 8.53 |
| Local (London) | 50 | 2107.3 | 18.65 |
| Remote (Ireland) | 10 | 415.9 | 23.24 |
| Remote (Ireland) | 25 | 1052.7 | 23.12 |
| Remote (Ireland) | 50 | 2084.8 | 23.07 |

### w:"majority" (adds shard1's replication-wait cost on top)

| Target | concurrency | ops/sec | p50 ms |
|---|---|---|---|
| Local (London) | 10 | 462.6 | 20.57 |
| Local (London) | 25 | 1161.1 | 20.77 |
| Local (London) | 50 | 1908.6 | 24.61 |
| Remote (Ireland) | 10 | 217.9 | 44.88 |
| Remote (Ireland) | 25 | 553.8 | 44.36 |
| Remote (Ireland) | 50 | 1081.3 | 44.15 |

**Findings:**

1. **mongos choice genuinely matters, and the cost is real.** Remote
   floor (~23ms `w:1`, ~45ms `w:"majority"`) vs local floor (~3ms
   `w:1`, ~20ms `w:"majority"`) — roughly 2x the single-hop cross-region
   RTT in both cases, consistent with paying the network cost twice:
   client→remote mongos→shard primary→back, rather than
   client→local mongos→shard primary→back.

2. **Remote latency is flat across concurrency; local rises with load.**
   Remote sits at ~23-24ms (`w:1`) regardless of 10, 25, or 50
   concurrent writers — the fixed double-hop network cost dominates
   and swamps any local queueing effect at these concurrency levels.
   Local numbers climb steadily with load (3.4ms → 18.7ms), the same
   saturation pattern seen in every other benchmark in this log.

3. **`w:"majority"` adds a consistent offset on top, doesn't change
   the local-vs-remote story.** Both local and remote floors shift up
   by roughly the same ~17-20ms (shard1's own replication-wait cost,
   independent of which mongos was used) — confirming this cost is
   shard-internal, not mongos-related, exactly as expected.

**Methodology note for the talk:** a real application normally
connects via a full seed list of all `mongos` hosts, letting the
driver auto-select and fail over on its own — this test deliberately
pinned to one specific router at a time to isolate the variable, which
is the right choice for measurement but not how a real app would
connect. Worth a one-line caveat on the slide.

**Not yet tested:** stopping a region's `mongos` entirely and
confirming an app using it fails over to a remote router — the actual
availability half of the story, versus the latency-cost half measured
here.

## Next up (Phase 5)

- Config server replica set (CSRS), 3 members, 1 per region — same
  region-tag pattern as the main replica set.
- Shard replica set(s) — start with 1 shard, each internally spread
  1-per-region, matching the original build plan's scope trim.
- `mongos` routers, 1 per region.
- Repeat the regional-outage scenario against the sharded cluster —
  one shard's region down, confirm `mongos`/unaffected-shard
  availability (slides 34–37's actual point).
