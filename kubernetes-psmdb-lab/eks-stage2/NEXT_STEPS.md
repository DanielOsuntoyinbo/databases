# Stage 2 — after `terraform apply`

## 1. Provision

cd terraform
terraform init
terraform plan -out=stage2.plan
terraform apply stage2.plan

## 2. Point kubectl at the new cluster

aws eks update-kubeconfig --region eu-west-1 --name psmdb-lab-stage2
kubectl get nodes -o wide

Confirm the three nodes report zones eu-west-1a, eu-west-1b, eu-west-1c under
topology.kubernetes.io/zone before going further.

## 3. Install the Percona Operator for MongoDB

helm repo add percona https://percona.github.io/percona-helm-charts
helm repo update
helm install psmdb-operator percona/psmdb-operator \
  --namespace psmdb --create-namespace \
  --version <pin the version you tested in stage 1>
kubectl -n psmdb get pods

## 4. Deploy the PerconaServerMongoDB custom resource

Use k8s/cr.yaml. Before applying:
- fill in the real bucket name from `terraform output backup_bucket_name`
- confirm the image and backup.image tags against the compatibility
  matrix for whatever crVersion you set

kubectl -n psmdb apply -f k8s/cr.yaml
kubectl -n psmdb get psmdb -w

### IRSA for backups — two-pass apply

terraform/backup-irsa.tf trusts a specific Kubernetes ServiceAccount name
(var.backup_service_account_name) via OIDC. That service account doesn't
exist until the CR above has been applied and the operator has created the
rs0 pods. Realistic order:

terraform apply -target=module.eks -target=module.vpc -target=kubernetes_storage_class.psmdb_gp3
kubectl -n psmdb apply -f k8s/cr.yaml
kubectl get sa -n psmdb
# update backup_service_account_name to match, then:
terraform apply

Confirm the role actually attached before trusting backups work:
kubectl exec -it <backup-agent-pod> -n psmdb -- printenv | grep AWS_ROLE_ARN

## 5. Validate the topology

kubectl -n psmdb get pods -o wide

Then from a mongo shell against the primary:
rs.status()
rs.conf()

Save both as your baseline before failure testing.

## 6. Failure testing

# single node
kubectl cordon <node-in-az-a>
kubectl drain <node-in-az-a> --ignore-daemonsets --delete-emptydir-data
kubectl -n psmdb get pods -o wide

# simulate full AZ loss
kubectl cordon <all nodes in az-a>
kubectl drain <all nodes in az-a> --ignore-daemonsets --delete-emptydir-data

Re-capture rs.status()/rs.conf() after each test.

## 7. Backup/restore drill

kubectl -n psmdb apply -f k8s/backup.yaml
kubectl -n psmdb get psmdb-backup -w

A completed backup only proves the upload worked — actually restore it into
a scratch namespace and query the data back out before calling this done.
