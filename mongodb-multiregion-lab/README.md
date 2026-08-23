# MongoDB Multi-Region Resilience Lab

**The hands-on lab behind my Percona Live 2026 session.**

Build it. Break it. Measure it. Recover it.

This repository contains the AWS infrastructure, MongoDB topologies, failure experiments, and captured evidence used to explore multi-region resilience in the talk. The lab is intentionally reusable beyond the conference: the infrastructure, runbooks, scenarios, and evidence are organised around MongoDB resilience concepts rather than slide numbers.

> **Implementation:** Percona Server for MongoDB (PSMDB) on AWS. The current lab pins PSMDB **7.0.39-21**.

## What this lab explores

The lab spans three AWS regions, treated as independent failure domains:

| Failure domain | AWS region | Role |
|---|---|---|
| London | `eu-west-2` | Primary-preferred region in the baseline replica set |
| Ireland | `eu-west-1` | Independent regional failure domain |
| Paris | `eu-west-3` | Independent regional failure domain |

The environment is used to answer practical questions such as:

- What happens when a primary fails?
- What happens when an entire region becomes unavailable?
- Why does majority placement matter more than simply counting regions?
- What does priority influence, and what does it not influence?
- What changes between `w:1` and `w: "majority"` across regions?
- What does an arbiter solve, and what does it not solve?
- How much latency does cross-region durability introduce?
- How do the same replica-set principles apply to a sharded cluster?
- How does the service recover when a failed region returns?

## Start here

Choose the path that matches what you want to do:

| I want to... | Go to |
|---|---|
| Understand the architecture and why it was built this way | [`docs/00-lab-architecture-and-build-plan.md`](docs/00-lab-architecture-and-build-plan.md) |
| See the concise measured results from the experiments | [`docs/01-evidence-log.md`](docs/01-evidence-log.md) |
| Read the full timelines, benchmark decomposition, anomalies and implementation findings | [`docs/03-detailed-findings.md`](docs/03-detailed-findings.md) |
| Rebuild the environment and replay the tests | [`docs/02-rebuild-and-test-runbook.md`](docs/02-rebuild-and-test-runbook.md) |
| Inspect the underlying captured output | [`docs/evidence-raw/`](docs/evidence-raw/) |

**Documentation model:** architecture = **why/what**, runbook = **how**, evidence log = **what happened**, detailed findings = **why the result is interesting**, raw evidence = **proof**.

## Lab architecture at a glance

```text
London (eu-west-2)       Ireland (eu-west-1)      Paris (eu-west-3)
Failure domain A         Failure domain B         Failure domain C
       │                        │                        │
       └──────────── AWS Transit Gateway mesh ──────────┘

Replica-set experiments:   MongoDB voting members distributed across regions
Sharded-cluster tests:     mongos + CSRS + shard replica set across regions
Automation:                Terraform + Ansible + Make
Evidence:                  rs.status(), rs.conf(), logs, latency and write tests
```

The baseline replica set uses one data-bearing voting member per region. Additional nodes allow alternate topologies to be constructed for majority-placement, even-vote, and arbiter experiments. The sharded environment uses regional `mongos` routers plus a three-member config server replica set and shard replica set distributed across the same failure domains.

## Experiment guide

These IDs are intended to remain stable even if the conference deck changes.

| ID | Experiment | Question |
|---|---|---|
| `RS-01` | Primary failure and election | How does MongoDB replace a failed primary? |
| `RS-02` | Regional failure with majority preserved | Can the replica set remain writable after losing a region? |
| `RS-03` | Even-vote topology | Why can a 2+2 split leave the deployment without a primary? |
| `RS-04` | Majority concentrated in one region | Why is an odd member count not enough by itself? |
| `RS-05` | Arbiter and election majority | What does an arbiter change about elections and durability? |
| `WC-01` | `w:1` vs `w: "majority"` | What acknowledgement and latency trade-offs appear across regions? |
| `LAT-01` | Cross-region latency | What cost does geography add to reads and writes? |
| `AZ-01` | Multi-AZ comparison | How does same-region placement differ from multi-region placement? |
| `SH-01` | Sharded-cluster regional outage | What survives when one region loses `mongos`, CSRS, and shard members? |
| `REC-01` | Recovering after majority loss | How can a badly placed replica set be recovered when the surviving side cannot form a majority? |

### Disaster recovery scope

Disaster recovery beyond MongoDB's normal high-availability mechanisms is treated as a **design boundary rather than a separate benchmark experiment** in this lab. Backup/restore and point-in-time recovery are recovery mechanisms for scenarios where normal HA cannot recover the database. The measured evidence here focuses on replica-set and sharded-cluster availability, quorum, failover, durability, topology placement and recovery behaviour.

For the exact commands and current topology prerequisites for implemented experiments, use the [rebuild and test runbook](docs/02-rebuild-and-test-runbook.md). For measured results, use the [evidence log](docs/01-evidence-log.md). For the richer technical narrative behind those results, including detailed election timings, WiredTiger restart evidence, Multi-AZ benchmark tables, arbiter/write-concern nuance, `mongos` locality and the full sharded-outage proof, use the [detailed findings](docs/03-detailed-findings.md).

## Build and replay

### Prerequisites

- Terraform >= 1.7.0
- AWS provider ~> 5.60
- An AWS credential/profile with access to `eu-west-2`, `eu-west-1`, and `eu-west-3`
- IAM permissions required by the Terraform modules
- SSH access and the Ansible vault material described in the runbook

### Base infrastructure

```bash
export AWS_PROFILE=psmdb-lab
make init
make plan
make apply
make site
```

Additional deployment and manual replay steps are documented in [`docs/02-rebuild-and-test-runbook.md`](docs/02-rebuild-and-test-runbook.md). Do not assume `make apply` + `make site` reproduces every experimental topology: some topology changes are intentionally replayed through `mongosh` and are documented explicitly in the runbook.

### Tear down when finished

```bash
make destroy
```

The lab spans multiple regions and uses resources such as Transit Gateway attachments and EC2 instances that incur cost while running. Tear the environment down between working sessions when it is not needed.

## Evidence-first approach

The goal of the lab is not simply to show a topology diagram. Each important claim should be backed by an experiment and observable output.

For a typical scenario, capture:

1. the topology before failure (`rs.conf()` / `rs.status()`),
2. the failure action and timestamp,
3. the election or availability outcome,
4. application/write behaviour where relevant,
5. the recovered state after services return.

The documentation intentionally has two evidence layers: the concise evidence log makes the results easy to scan, while the detailed findings preserve the richer investigative context instead of throwing it away. `evidence-raw/` remains the underlying source for checking the claims.

That makes the material useful in three ways: **learn the concept → reproduce the failure → inspect the evidence**.

## Percona Live 2026

For the talk, the experiments are presented in roughly the same learning sequence as the session: failure domains → elections and majority → topology placement → write concern and latency → arbiters → sharded-cluster resilience → recovery.

The experiment IDs above are deliberately independent of slide numbers. This keeps the repository useful as the presentation evolves and after the conference is over.

## Repository structure

```text
mongodb-multiregion-lab/
├── README.md
├── Makefile
├── infrastructure/
│   ├── terraform/
│   └── ansible/
└── docs/
    ├── 00-lab-architecture-and-build-plan.md
    ├── 01-evidence-log.md
    ├── 02-rebuild-and-test-runbook.md
    ├── 03-detailed-findings.md
    └── evidence-raw/
```

## Reproducibility note

Infrastructure and baseline configuration are automated. Some experimental topology changes were performed manually during the original testing and are replayed through documented `mongosh` steps. Where automation does not yet reproduce a state end-to-end, the runbook calls that out rather than implying otherwise.

---

**For conference attendees:** start with the [experiment guide](#experiment-guide), then open the evidence log for the scenario you want to inspect. Use the detailed findings when you want the deeper technical reasoning and exact measured context behind a slide.

**For future lab work:** use the architecture document and runbook as the stable foundation, and add new scenarios/evidence without coupling them to presentation slide numbers.
