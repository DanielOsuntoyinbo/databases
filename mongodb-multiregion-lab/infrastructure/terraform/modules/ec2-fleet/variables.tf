variable "name" {
  description = "Name prefix for this region's fleet resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC to launch instances and the security group into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch instances into"
  type        = string
}

variable "node_role" {
  description = "Role tag for these nodes, e.g. replicaset, configsvr, shard, mongos"
  type        = string
}

variable "node_count" {
  description = "Number of instances of this role to launch in this region"
  type        = number
  default     = 1
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "ami_id" {
  description = "Override AMI ID. Leave null to use the latest Ubuntu 24.04 (Noble) AMI in this region."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Public key content (not a path) to install as this region's admin key pair"
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Admin workstation's public IP in CIDR form (x.x.x.x/32), the only source allowed to SSH in"
  type        = string
}

variable "mongod_ingress_cidrs" {
  description = "VPC CIDRs allowed to reach port 27017 — local VPC + peer region VPCs, never 0.0.0.0/0"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
