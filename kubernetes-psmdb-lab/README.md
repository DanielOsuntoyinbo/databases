# Percona Server for MongoDB on Kubernetes

Companion lab to [`mongodb-multiregion-lab`](https://github.com/DanielOsuntoyinbo/databases/tree/main/mongodb-multiregion-lab)
— replicating the same category of MongoDB resilience testing (primary
failure, election behavior, majority-loss recovery) using the
**Percona Operator for MongoDB on Kubernetes**, instead of self-managed
PSMDB on raw EC2.

## Why a separate repo

Different toolchain entirely — Kubernetes + the Percona Operator's
CRDs, not Terraform/Ansible against EC2 instances. Keeping it separate
avoids mixing two unrelated infrastructure approaches in one place.

## Structure

```
docs/
  00-build-plan.md       — staged plan, what's done, troubleshooting notes
manifests/
  cr-stage1-local.yaml   — Custom Resource for the local (Rancher Desktop) baseline
```

## Current status

**Stage 1 (local, Rancher Desktop): done.** Plain 3-member replica set,
verified healthy, matching the original EC2 lab's starting baseline.
See `docs/00-build-plan.md` for the full build log, including real
issues hit and fixed along the way (pod anti-affinity on single-node
clusters, resource sizing, a Rancher Desktop VM-driver bug).

**Stages 2 (EKS, multi-AZ) and 3 (EKS, multi-region): not started.**
