# MongoDB Multi-Region Resilience Lab — Architecture & Build Plan

This document explains **why the lab is designed this way and what it builds**.

The lab currently supports the Percona Live 2026 talk, but the architecture and experiment IDs are deliberately conference-neutral so the environment remains useful after the talk.

- **How to rebuild and run experiments:** `02-rebuild-and-test-runbook.md`
- **Measured results:** `01-evidence-log.md`
- **Raw captures:** `evidence-raw/`

Percona Server for MongoDB (PSMDB) is used to provide direct access to replica-set configuration, logs, elections and sharded-cluster behaviour.

---

## 1. Region and failure-domain model

| Region | AWS code | Lab role |
|---|---|---|
| London | `eu-west-2` | Failure domain A — primary-preferred region |
| Ireland | `eu-west-1` | Failure domain B |
| Paris | `eu-west-3` | Failure domain C |

Each region is treated as a separate failure domain. Each VPC also spans two AZs so the lab can compare **multi-AZ** and **multi-region** behaviour without adding another region.

The important abstraction is the failure domain, not the AWS region name: the experiments ask which voting members, data copies, routing components and application paths survive when a domain disappears.

---

## 2. Network architecture — AWS Transit Gateway

AWS Transit Gateway is regional, so the three-region mesh uses one TGW per region plus inter-region TGW peering and route propagation.

```
eu-west-2 (London)          eu-west-1 (Ireland)         eu-west-3 (Paris)
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│ VPC 10.10.0.0/16│         │ VPC 10.20.0.0/16│         │ VPC 10.30.0.0/16│
│  AZ-a  AZ-b      │         │  AZ-a  AZ-b      │         │  AZ-a  AZ-b      │
│   TGW-lon        │◄──peer─►│   TGW-ire        │◄──peer─►│   TGW-par        │
└─────────────────┘         └─────────────────┘         └─────────────────┘
          └────────────────────peer (lon↔par)────────────────────┘
```

Design choices:

- Non-overlapping regional CIDRs: `10.10.0.0/16`, `10.20.0.0/16`, `10.30.0.0/16`.
- Three TGW peering attachments: London↔Ireland, Ireland↔Paris, London↔Paris.
- Regional route tables advertise the local VPC and routes to both peer CIDRs.
- MongoDB nodes do not require unrestricted public database ingress.
- Security groups restrict MongoDB traffic to the lab networks/admin path rather than `0.0.0.0/0`.

The network layer is intentionally visible in the lab because database resilience depends on more than `mongod`: routing and infrastructure are part of the service path being tested.

---

## 3. Compute and MongoDB layers

This is a resilience lab, not a production sizing or load-test reference.

| Role | Count | Instance type | Purpose |
|---|---:|---|---|
| Main replica-set members | 3 baseline | `t3.medium` | Elections, quorum, priority, write concern, regional failure |
| Extra replica-set members | scenario-dependent | `t3.medium` | 2+2, 2+2+1 and region-majority experiments |
| Config server replica set | 3 | `t3.medium` | 1 config-server member per region |
| Shard 1 replica set | 3 | `t3.medium` | 1 shard member per region |
| `mongos` routers | 3 | `t3.small` | 1 router per region |
| Multi-AZ comparison RS | 3 | `t3.medium` | Same-region comparison topology |

PSMDB is installed/configured with Ansible; infrastructure is provisioned with Terraform.

**Cost:** TGW attachments and EC2 instances incur charges while running. Use `make destroy` when the lab is not required.

---

## 4. Baseline replica-set topology

The baseline replica set has three voting, data-bearing members:

- London — primary-preferred (`priority: 3`)
- Ireland — `priority: 2`
- Paris — `priority: 1`

Members are tagged by region so the failure-domain mapping is visible in `rs.conf()`.

The baseline deliberately has **no arbiter**. Arbiter behaviour is introduced only for the relevant experiment so it can be compared with data-bearing voting members.

This topology is the starting point for the `RS-*`, `WC-*` and `LAT-*` experiments.

---

## 5. Sharded-cluster topology

The sharded lab applies the same replica-set reasoning to each MongoDB layer:

- **Config server replica set (CSRS):** 3 members, one per region.
- **Shard 1 replica set:** 3 members, one per region.
- **`mongos`:** 3 routers, one per region.

The purpose is not to demonstrate every sharding feature. It is to test whether the **sharded service path** remains usable when a region is unavailable and the CSRS and shard replica sets still preserve majority.

Zone sharding and geo-pinned chunk placement are intentionally outside the current talk scope.

---

## 6. Latency strategy

The lab records real AWS inter-region latency and uses it to compare operations such as `w:1` and `w:"majority"`.

A `latency-inject` role exists for controlled experiments, but the evidence currently used in the talk comes from **organic AWS backbone latency**, not synthetic `tc netem` delay. This keeps measured latency claims tied to the actual environment used for the tests.

---

## 7. Stable experiment catalogue

Experiment IDs are permanent. Slide numbers are deliberately not embedded in scenario names because the presentation can change while the lab remains useful.

| ID | Experiment | Question answered | Evidence |
|---|---|---|---|
| `RS-01` | Primary failure and election | What happens when the current primary disappears? | `rs.status()`, election logs, timing |
| `RS-02` | Regional failure with majority preserved | Does a correctly distributed topology remain writable? | member state + write outcome |
| `RS-03` | Even-vote topology | Why can 2+2 lose availability? | majority/election refusal + write failure |
| `RS-04` | Region-majority anti-pattern | Why is an odd member count alone not enough? | 2+3 placement + regional outage outcome |
| `RS-05` | Arbiter and election majority | What does an arbiter restore, and what does it not provide? | election result + write-concern behaviour |
| `WC-01` | `w:1` vs `w:"majority"` | What durability/latency trade-off is measurable? | benchmark results |
| `READ-01` | Read preference | How does read routing affect latency/load? | benchmark results |
| `LAT-01` | Multi-region vs Multi-AZ latency | What cost does geography introduce? | measured latency/throughput |
| `SH-01` | Sharded regional outage | Does the sharded service survive loss of one region? | CSRS/shard state + client result |
| `REC-01` | Recover after majority loss | How can an already-unavailable replica set be recovered? | **Planned — evidence not yet captured** |
| `DR-01` | Recover when HA is insufficient | How does backup/PITR-based disaster recovery differ from HA? | **Planned** |

The Percona Live deck maps to these IDs; the IDs do not depend on the deck.

---

## 8. Evidence model

For each experiment, aim to preserve four things:

1. **Before** — topology/configuration and healthy state.
2. **Failure/action** — exactly what was stopped, changed or measured.
3. **Observed result** — MongoDB state, client outcome and relevant logs.
4. **Recovery** — how the service returned to the intended steady state.

`01-evidence-log.md` interprets the results. `evidence-raw/` preserves the underlying captures so claims can be checked rather than accepted from the slides alone.

---

## 9. Repository shape

```text
mongodb-multiregion-lab/
├── README.md                         # conference-focused front door
├── Makefile
├── infrastructure/
│   ├── terraform/
│   └── ansible/
├── docs/
│   ├── 00-lab-architecture-and-build-plan.md   # why / what
│   ├── 01-evidence-log.md                      # what happened
│   ├── 02-rebuild-and-test-runbook.md          # how
│   └── evidence-raw/                            # proof
└── write_read_latency.py
```

The README can become conference-neutral after Percona Live without requiring the lab itself to be reorganized.

---

## 10. Build order

1. **Network foundation** — VPCs, TGWs, peering, routes and security groups.
2. **Baseline replica set** — build and verify the 1+1+1 topology.
3. **Measurement tooling** — write concern, read preference and latency benchmarks.
4. **Alternate voting topologies** — 2+2, arbiter, region-majority placement.
5. **Multi-AZ comparison** — isolate same-region versus cross-region effects.
6. **Sharded cluster** — CSRS, shard replica set and regional `mongos` routers.
7. **Evidence pass** — capture reproducible before/failure/result/recovery artifacts.
8. **Recovery/DR extensions** — add `REC-01` and `DR-01` only after their tests are actually performed.

This order keeps the core replica-set experiments usable even while later scenarios are still being built.

---

## 11. Scope and reproducibility

Infrastructure and baseline configuration are automated. Some experimental topology transitions were performed manually through `mongosh` and are intentionally documented in the runbook rather than hidden.

The goal is not to claim production readiness. The goal is a **reproducible environment for reasoning about MongoDB resilience using measured evidence**.
