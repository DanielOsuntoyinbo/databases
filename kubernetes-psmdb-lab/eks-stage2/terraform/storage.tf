provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

resource "kubernetes_storage_class" "psmdb_gp3" {
  metadata {
    name = "psmdb-gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"

  # WaitForFirstConsumer is the part that actually matters here - it
  # delays PV provisioning until the pod is scheduled, so the volume
  # lands in the same AZ as the pod instead of the CSI driver guessing
  volume_binding_mode = "WaitForFirstConsumer"

  reclaim_policy         = "Retain" # don't lose a PV to an accidental PVC delete mid-lab
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
