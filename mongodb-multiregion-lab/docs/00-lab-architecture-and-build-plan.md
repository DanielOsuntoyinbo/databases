# PSMDB Multi-Region Lab — Architecture & Build Plan

Repo: `github.com/DanielOsuntoyinbo/databases` → `mongodb-multiregion-lab/`
Purpose: live, prod-like PSMDB infra across 3 AWS regions to generate real
evidence (`rs.status()`, `rs.conf()`, election logs, measured latency,
write-concern behaviour) for the Percona Live 2026 talk, sections 2–6
(slides 11–37).

---

## 1. Region / failure-domain layout

| Region | AWS code | Role in talk terms |
|---|---|---|
| London | `eu-west-2` | Failure domain A — primary-preferred region |
| Ireland | `eu-west-1` | Failure domain B |
| Paris | `eu-west-3` | Failure domain C |

Each region = one VPC = one "failure domain" for slides 6, 13, 14, 18, 19.
Each VPC gets 2 AZs internally so you can *also* show multi-AZ vs
multi-region (slide 8) without extra regions — one region's two AZs stand
in for "same failure domain, different rack/AZ."

---

## 2. Network architecture — AWS Transit Gateway

TGW is regional, so "one TGW mesh across 3 regions" actually means: one
TGW per region + inter-region TGW peering attachments between all three,
plus TGW route tables propagating each VPC's CIDR to the other two.

```
eu-west-2 (London)          eu-west-1 (Ireland)         eu-west-3 (Paris)
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│ VPC 10.10.0.0/16│         │ VPC 10.20.0.0/16│         │ VPC 10.30.0.0/16│
│  AZ-a  AZ-b      │         │  AZ-a  AZ-b      │         │  AZ-a  AZ-b      │
│   TGW-lon         │◄──peer─►│   TGW-ire         │◄──peer─►│   TGW-par         │
└─────────────────┘         └─────────────────┘         └─────────────────┘
          └────────────────────peer (lon↔par)────────────────────┘
```

- Non-overlapping CIDRs per region (10.10/10.20/10.30) — required for TGW
  peering route propagation.
- 3 peering attachments total (full mesh: lon↔ire, ire↔par, lon↔par).
- TGW route tables: each region propagates its VPC CIDR and accepts
  routes to the other two.
- No NAT/public ingress on the mongod/mongos/configsvr nodes — a bastion
  or SSM Session Manager per region for admin access, matching your "no
  hardcoded IPs, least privilege" pattern from the Postgres build.
- Security groups: allow 27017 (mongod), 27019 (configsvr), 27018
  (shard mongod, if you separate the port) only from the other two
  regions' CIDRs + the bastion SG. No 0.0.0.0/0 anywhere.

This is deliberately more than the talk's lab needs strictly requires —
you picked TGW because it's what a real regionally-resilient deployment
would use, and it gives you a legitimate "here's the routing/
infrastructure layer" visual for slide 28 (application → MongoDB →
network/routing → infrastructure).

---

## 3. Compute sizing

Lab, not load-test — small, cheap, and torn down between sessions.

| Role | Count | Instance type | Notes |
|---|---|---|---|
| Replica-set mongod (unsharded RS demo) | 3 (1/region) | `t3.medium` | 2 vCPU/4GB is enough for `rs.status()`-driven demos |
| Config server RS | 3 (1/region) | `t3.medium` | CSRS, per MongoDB best practice, always PSA-capable but here PSS |
| Shard 1 RS | 3 (1/region) | `t3.medium` | |
| Shard 2 RS | 3 (1/region) | `t3.medium` | Optional — add only if you want to show balancer/chunk behaviour; can start with 1 shard and add a second live on stage if you want that visual |
| `mongos` router | 1/region (3 total) | `t3.small` | Stateless, colocate near app tier per region |
| Bastion/SSM host | 1/region (3 total) | `t3.micro` | Or skip entirely and use SSM Session Manager with no bastion box |

Everything is EC2 + PSMDB installed via Ansible (matches your existing
pattern), not Atlas/DocumentDB — you want raw `rs.conf()`/`rs.status()`
control for the demos.

**Cost flag:** TGW has an hourly charge per attachment plus per-GB data
processing, on top of 20+ EC2 instances across 3 regions. Worth scripting
a clean `terraform destroy` between working sessions rather than leaving
this running — I'll build the Makefile targets for that from the start,
same as `make inventory` in the Postgres repo.

---

## 4. MongoDB topology — unsharded replica set (slides 13–26)

- 3 voting data-bearing members, 1 per region: `rs-lon-1`, `rs-ire-1`,
  `rs-par-1`.
- Default: `priority` slightly higher on `rs-lon-1` (primary-preferred
  region) to give you a clean "why did MongoDB elect *this* member"
  story for slide 21.
- No arbiter in the baseline topology — you add one live for slide 26 to
  show the vote-without-data distinction, then remove it again. I'll
  build the Ansible role so an arbiter is a single var flip
  (`arbiter_enabled: true`) rather than a manual `rs.addArb()` you have
  to remember.
- `rs.conf()` will show `members[n].tags` set to `{region: "lon"}` /
  `"ire"` / `"par"} `so failure-domain mapping (slide 14) is visible
  directly in config, not just inferred from IP.

## 5. MongoDB topology — sharded cluster (slides 34–37)

- 1 config server replica set (CSRS), 3 members, 1 per region — same
  region-tag pattern as above.
- 1–2 shard replica sets, each internally spread 1-per-region (not
  1-shard-per-region) — this is the realistic pattern and lets every
  shard independently survive a single-region loss, which is the point
  you're making in slide 35.
- 3 `mongos` routers, 1 per region, each region's app tier talks to its
  local `mongos` — gives you the "mongos/routing availability" visual
  for slide 35 without needing a full app tier.
- Deliberately not going deep on zone sharding / geo-pinned chunks
  unless you want slide 34–37 to grow — flag if that changes scope,
  it's a meaningfully bigger build (shard key + zone range config).

---

## 6. Latency simulation (slides 24–25)

Real inter-region RTT (London↔Ireland ~10-15ms, London↔Paris ~8-12ms,
Ireland↔Paris ~15-20ms) is already present from physical distance, but
for a **repeatable, on-stage demo** you want deterministic, controlled
values rather than whatever the internet gives you that day.

Plan: `tc netem` on each node's TGW-facing interface, applied via an
Ansible role (`latency-inject`) with a var like:

```yaml
latency_profile:
  lon_to_ire_ms: 40
  lon_to_par_ms: 30
  ire_to_par_ms: 50
```

Applied/removed with a single playbook run — so mid-talk you can go from
"baseline real RTT" to "simulated 40ms" to back-to-baseline without
touching individual boxes. This directly produces the "before/after"
measured write-latency evidence for slide 25.

---

## 7. Test scenario catalogue (maps 1:1 to your slide deck)

| Slides | Scenario | Lab action | Evidence captured |
|---|---|---|---|
| 16–17 | Primary failure & election | `sudo systemctl stop mongod` on current primary | `rs.status()` before/after, election log lines |
| 18 | Regional outage | Stop all region members via one Ansible play (`--limit region_ire`) | `rs.status()` showing 2/3 domains up, majority-writable |
| 19 | Same outage, different topology | Re-run 18 against an alternate `rs.conf()` (e.g. 2 votes in one region) | Two `rs.conf()` + two outcome states |
| 20–21 | Votes/priority | Change `priority`/`votes` live, force election | `rs.conf()` diff + resulting primary |
| 22–23 | w:1 vs w:majority | Scripted writes with each write concern, killing majority regions between runs | Acknowledgement latency + success/fail per write |
| 24–25 | Latency impact | Toggle `latency_profile`, repeat write-concern test | Latency numbers + write time comparison |
| 26 | Arbiter | Flip `arbiter_enabled`, force election with arbiter counted | `rs.status()` showing non-data-bearing voter |
| 30–32 | Recovery / RTO-RPO | Restore stopped region, watch catch-up | `rs.status()` lag decreasing to 0, timestamped |
| 34–37 | Sharded resilience | Repeat 18 against sharded cluster, one shard's region down | `sh.status()` / `mongos` availability, unaffected shards still routable |

I'll build these as numbered scripts (`scenarios/16-primary-failure.sh`,
etc.) that both run the scenario **and** dump timestamped `rs.status()`/
`rs.conf()`/log output to a `evidence/` directory — so every slide has a
committed, reproducible artifact behind it, not a live demo you're
praying works on the day.

---

## 8. Repo layout

```
databases/
└── mongodb-multiregion-lab/
    ├── README.md
    ├── Makefile                    # plan/apply/destroy/inventory/scenario targets
    ├── infrastructure/
    │   ├── terraform/
    │   │   ├── modules/
    │   │   │   ├── vpc/
    │   │   │   ├── tgw/
    │   │   │   ├── tgw-peering/
    │   │   │   └── ec2-fleet/
    │   │   ├── regions/
    │   │   │   ├── london/
    │   │   │   ├── ireland/
    │   │   │   └── paris/
    │   │   └── global/              # cross-region peering + route tables
    │   └── ansible/
    │       ├── roles/
    │       │   ├── common/
    │       │   ├── psmdb/
    │       │   ├── replicaset/
    │       │   ├── configsvr/
    │       │   ├── shard/
    │       │   ├── mongos/
    │       │   └── latency-inject/
    │       └── group_vars/
    ├── scenarios/                    # numbered scenario scripts, per table above
    └── evidence/                     # gitignored or LFS — timestamped rs.status()/logs output
```

Same shape as `postgres-homelab` — Terraform for provisioning, modular
Ansible roles, `make inventory` generating dynamic inventory from
Terraform outputs.

---

## 9. Build phases

1. **Network foundation** — 3 VPCs, 3 regional TGWs, 3 peering
   attachments, route propagation, security groups. Verify cross-region
   ping/connectivity before touching MongoDB at all.
2. **Unsharded replica set** — `psmdb`/`replicaset` Ansible roles, region
   tags, priority config. Get slides 13–21 evidence-producible first
   since that's the core of the talk.
3. **Write concern + latency tooling** — `latency-inject` role, write
   concern test scripts. Produces slides 22–25 evidence.
4. **Arbiter toggle + recovery scenarios** — slides 26, 30–32.
5. **Sharded cluster** — CSRS, shard RS(s), `mongos`. Slides 34–37.
6. **Scenario scripts + evidence capture** — the numbered scripts in
   section 7, wired to dump reproducible output per slide.

Recommend building and validating in that order rather than standing up
the full sharded topology on day one — phases 1–4 alone cover the
highest-value slides (15–26) and let you start rehearsing those sections
while sharding is still being built.

---

## 10. Open items to confirm before Phase 1 code

- PSMDB version to standardise on (align with your Postgres homelab's
  PGDG-pinned-version discipline — want a specific PSMDB release pinned,
  not "latest").
- Whether you want TLS between members from the start (prod-realistic,
  matches your no-hardcoded-secrets pattern) or defer it to a later
  pass.
- Auth: keyfile vs x.509 for intra-cluster auth.
- Whether `evidence/` gets committed to git (talk material) or lives
  outside the repo.
