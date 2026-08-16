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

## 5. Primary failure, election & recovery (slides 16–17, 30–32)

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

## 6. 2+2+1 topology: even-vote-count anti-pattern & partition demo (slides 8, 10, 19, 26)

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

## Next up (Phase 4)

- Arbiter toggle (slide 26): add/remove a non-data-bearing voter,
  observe `rs.status()` vote distribution.
- Regional outage (slide 18): stop all members in one region via
  Ansible `--limit`, capture majority-writable state with 2/3 up.
- Same outage, different topology (slide 19): alter `rs.conf()`
  (e.g. different vote distribution), repeat the outage, compare.
- Priority change (slide 21 continuation): flip priorities live, force
  election, capture resulting primary.
