# Percona Server for MongoDB on Kubernetes — Build Plan

Companion effort to the self-managed EC2 multi-region PSMDB lab
(`github.com/DanielOsuntoyinbo/databases`, `mongodb-multiregion-lab/`),
kept as a separate repo since the toolchain is entirely different
(Kubernetes + the Percona Operator, not Terraform/Ansible on raw EC2).

Goal: replicate the same category of resilience testing (primary
failure, election behavior, majority-loss recovery, etc.) on
Kubernetes, and compare operator-managed automatic behavior against
the manual `mongosh`-driven approach used in the EC2 lab.

## Staged plan

| Stage | Topology | Status |
|---|---|---|
| 1 | Local Kubernetes (Rancher Desktop), single node, plain 3-member replica set | ✅ Done |
| 2 | Single AWS EKS cluster, multi-AZ | ✅ Done |
| 3 | Multiple EKS clusters across regions (true multi-region) | ⬜ Not started |

Stage 1 is deliberately the cheapest, lowest-risk place to learn the
Percona Operator's mechanics before spending anything on real
infrastructure. Stages 2 and 3 move to AWS EKS once the operator's
behavior is well understood locally.

## Stage 1 — Local (Rancher Desktop)

### Environment
- Local Kubernetes via Rancher Desktop (not Minikube — already
  installed; functionally equivalent for this purpose since both are
  disposable, single-node local Kubernetes tools). Cluster runs `k3s`
  under the hood (`lima-rancher-desktop` node).
- Percona Operator for MongoDB **v1.23.0**
  (`https://docs.percona.com/percona-operator-for-mongodb/latest/`)
- PSMDB image: `percona/percona-server-mongodb:8.0.26-11`

### Deployment
```bash
kubectl create namespace psmdb
kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-server-mongodb-operator/v1.23.0/deploy/bundle.yaml -n psmdb
kubectl apply -f manifests/cr-stage1-local.yaml -n psmdb
```

The stock `deploy/cr.yaml` defaults to a **sharded** cluster (3 mongod
+ 3 mongos + 3 config servers). For a direct comparison against the
EC2 lab's original baseline (a plain 3-member replica set), two
changes were made — see `manifests/cr-stage1-local.yaml`:
- `sharding.enabled: false`
- `replsets[0].affinity.antiAffinityTopologyKey: "none"` (see below —
  required for single-node clusters specifically)

### Verified working state

```
rs0-0.my-cluster-name-rs0...  PRIMARY    health=1
rs0-1.my-cluster-name-rs0...  SECONDARY  health=1
rs0-2.my-cluster-name-rs0...  SECONDARY  health=1
```

Connection (the direct, non-SRV form — see troubleshooting below for
why):
```bash
mongosh "mongodb://databaseAdmin:<password>@my-cluster-name-rs0.psmdb.svc.cluster.local:27017/admin?directConnection=true"
```
Retrieve the actual admin password at deploy time via:
```bash
kubectl get secret my-cluster-name-databaseadmin-conn-str -n psmdb \
  -o jsonpath='{.data.databaseAdmin_rs0_connectionStringSrv}' | base64 --decode && echo
```

### Troubleshooting notes (worth keeping — real issues hit, not
hypothetical)

**1. Pod anti-affinity blocks scheduling on single-node clusters.**
The default CR sets `antiAffinityTopologyKey: "kubernetes.io/hostname"`
for the `rs0` replset — sensible for real production (never colocate
replica set members on the same node), but on a single-node local
cluster it makes every member beyond the first permanently
unschedulable (`FailedScheduling: 0/1 nodes are available: 1 node(s)
didn't match pod anti-affinity rules`). Fixed by setting it to
`"none"` for local development. **This must be reverted to
`"kubernetes.io/hostname"` (or a topology-aware key like
`topology.kubernetes.io/zone`) for stages 2/3 on real multi-node
infrastructure** — it's a local-only workaround, not a production
setting.

**2. Resource starvation causes liveness-probe timeouts, not obvious
errors.** Rancher Desktop's factory-default VM allocation (2 CPU /
4GB) was insufficient to run even 2 of 3 replica set pods reliably —
each pod runs 4 containers (`mongod`, `backup-agent`, `logs`,
`logrotate`), and the `mongod` liveness probe (a real MongoDB health
check with a 10s timeout) started failing under contention, causing a
`CrashLoopBackOff` that looked like a MongoDB problem but was actually
a host-resource problem. Fixed by raising the VM to 4 CPU / 6GB via
`rdctl set --virtual-machine.memory-in-gb 6 --virtual-machine.number-cpus 4`.
**Lesson for stage 2/3:** don't assume a crash loop is
MongoDB-specific — check the actual resource requests/limits and node
capacity first.

**3. Rancher Desktop's Preferences GUI locks Hardware sliders while
the backend is running** — they display current values but don't
respond to drag input in that state. Use `rdctl set` instead, which
handles the stop/reconfigure/restart sequence internally.

**4. `rdctl set` can leave the VM driver in a broken state.** After
changing resources and doing a normal `rdctl shutdown` / `rdctl
start`, the backend came back reporting `"host agent is running but
driver is not"` — a known, unresolved Rancher Desktop bug (confirmed
via multiple GitHub issues: `rancher-sandbox/rancher-desktop#6286`,
`#9281`, `#5481` — all show the identical error with no clean
incremental fix). The working fix was a full reset:
```bash
rdctl reset --factory   # rdctl factory-reset is deprecated, same command
```
This wipes `~/.rd/` including the `rdctl`/`kubectl`/`docker` PATH
shims — relaunch via `/opt/rancher-desktop/rancher-desktop` directly
the first time, since `rdctl` itself won't exist until the app
regenerates those shims on startup. Everything in the cluster
(namespace, operator, CR) needs to be redeployed after a factory
reset; this local `cr.yaml` file itself is unaffected since it's just
a file on disk, not cluster state.

**5. `mongodb+srv://` connection strings default to TLS and failed to
connect** (`self-signed certificate in certificate chain` on one
attempt, `connection <monitor> ... closed` on a retry with
`tlsAllowInvalidCertificates=true`). The operator's internal TLS uses
a self-signed CA by default (`--tlsMode=preferTLS
--sslAllowInvalidCertificates` in the `mongod` args). The plain,
non-SRV `mongodb://` form with `directConnection=true` connected
successfully without needing to resolve the TLS issue — used as the
working method for this stage rather than debugging the SRV path
further, since it wasn't blocking anything.

## Stage 2 — AWS EKS (multi-AZ)

### Environment
- EKS cluster provisioned via Terraform (not eksctl), eu-west-1, node
  group spread across 3 AZs (m6i.large, one node per AZ)
- `terraform-aws-modules` for VPC and EKS; EBS CSI driver via IRSA;
  storage class `psmdb-gp3` with `WaitForFirstConsumer` binding mode
- Percona Operator v1.23.0 (same version as stage 1), installed via Helm

### Notable events / findings

**1. `psmdb-lab-terraform` IAM user needed explicit grants beyond EC2.**
S3, CloudWatch Logs, and IAM role/policy creation all returned
`AccessDenied` on first apply. Required a root/admin-granted policy
covering `iam:CreateRole`/`CreatePolicy`, `logs:CreateLogGroup`, and
`s3:CreateBucket` before Terraform could proceed.

**2. Cluster creator gets zero in-cluster RBAC by default.** The
`terraform-aws-modules/eks` module's
`bootstrap_cluster_creator_admin_permissions` defaults to `false`, so
the identity running Terraform could authenticate to the API server
but had no permissions inside it (`Unauthorized` on the Kubernetes
provider's storage class resource). Fixed with an explicit
`access_entries` block granting the Terraform identity
`AmazonEKSClusterAdminPolicy` at cluster scope — additive, no cluster
recreation needed.

**3. IRSA for PBM backups initially bound to a guessed ServiceAccount
name that didn't exist.** The mongod pods ran under the namespace's
`default` SA, which had no IRSA annotation — PBM got `403 Forbidden`
from S3. Fixed properly (not with a `default`-SA workaround) by
creating a dedicated `psmdb-lab-stage2-backup` ServiceAccount via
Terraform, referencing it explicitly via `serviceAccountName` in the
CR's `replsets[]` block, and pointing the IAM trust policy at its
actual name.

**4. Single-node failure test surfaced a real capacity gap.**
Cordoning/draining the primary's node caused a new primary election
within `electionTimeoutMillis` (confirmed via `rs.status()`), but the
rescheduled pod sat `Pending` — the node group had exactly 3 nodes for
3 pods with no spare CPU, so there was nowhere for the pod to go.
Required a manual `uncordon` to recover. This is a node-group sizing
gap, not an operator or MongoDB problem — full auto-recovery testing
needs Cluster Autoscaler (or standing headroom) in place first.

### Verification
- `rs.conf()` confirmed one member per AZ via node tags — see
  `eks-stage2/evidence/baseline-rs-conf.txt` and
  `baseline-rs-status.txt`
- Backups confirmed reaching S3 via the dedicated IRSA-bound
  ServiceAccount (no more `PBM Agent is not OK` in operator logs)
- Primary-failure / election-timing comparison against the EC2 lab's
  `systemctl kill` + `rs.status()` approach: **not yet complete** —
  election itself worked, but the pod-scheduling gap above interrupted
  clean auto-recovery, so the comparison wouldn't yet reflect a
  properly self-healing setup

### Cost note
Left running ~1 week: ~$295 AWS cost (EKS control plane, 3x NAT
gateways — both hourly and per-GB data processing — 3x on-demand EC2,
CloudWatch ingestion from `audit`+`authenticator` log types). Infra
fully torn down via `terraform destroy` afterward, confirmed via
`describe-volumes`/`describe-nat-gateways`/`list-clusters` all
returning empty. Future operator/deployment mechanics testing moved to
a local multi-node `kind` cluster (nodes labeled with
`topology.kubernetes.io/zone` to simulate AZ spread) to avoid further
cloud cost; AWS reserved for short, bounded sessions validating
cloud-specific behavior (IRSA, real zonal EBS failure).

## Next steps (Stage 3)

- Add Cluster Autoscaler (or Karpenter) so a pending pod with an
  unsatisfiable zonal constraint triggers a new node in the correct AZ
  automatically — needed before stage 2's failure test can be called
  complete
- Re-run the primary-failure / election-timing comparison against the
  EC2 lab once the above is in place
- Multiple EKS clusters across regions using the operator's Main/
  Replica cross-site replication (`unmanaged: true` on non-Main
  clusters), manual TLS/encryption-key secret propagation between
  clusters, and either plain LoadBalancer/NLB exposure or Multi-Cluster
  Services for cross-cluster reachability
