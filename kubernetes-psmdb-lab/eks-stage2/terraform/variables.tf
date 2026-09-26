variable "region" {
  description = "AWS region for the stage 2 cluster"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "psmdb-lab-stage2"
}

variable "kubernetes_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.60.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread nodes and subnets across"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "node_instance_type" {
  description = "Instance type for the PSMDB node group"
  type        = string
  default     = "m6i.large"
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}
