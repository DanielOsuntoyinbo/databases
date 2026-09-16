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
| 2 | Single AWS EKS cluster, multi-AZ | ⬜ Not started |
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

## Next steps (Stage 2)

- Provision an EKS cluster (single region, multi-AZ node groups).
- Revert the anti-affinity workaround to a real topology key
  (`topology.kubernetes.io/zone` for multi-AZ spread).
- Re-run the baseline verification, then begin replaying EC2-lab-style
  tests (primary failure, election timing) and compare operator
  auto-recovery against the manual `systemctl kill` + `rs.status()`
  approach from the EC2 lab.
