variable "project_name" {
  description = "Name prefix applied to all resources"
  type        = string
  default     = "psmdb-multiregion-lab"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "lab"
}

# Non-overlapping CIDRs are required for TGW peering route propagation
# to work at all — kept as one map here so it's obvious at a glance
# that none of the three ranges collide.
variable "regions" {
  description = "Per-region network definitions for the 3 lab failure domains"
  type = map(object({
    aws_region          = string
    vpc_cidr            = string
    public_subnet_cidrs = list(string)
    azs                 = list(string)
  }))

  default = {
    london = {
      aws_region          = "eu-west-2"
      vpc_cidr            = "10.10.0.0/16"
      public_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]
      azs                 = ["eu-west-2a", "eu-west-2b"]
    }
    ireland = {
      aws_region          = "eu-west-1"
      vpc_cidr            = "10.20.0.0/16"
      public_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24"]
      azs                 = ["eu-west-1a", "eu-west-1b"]
    }
    paris = {
      aws_region          = "eu-west-3"
      vpc_cidr            = "10.30.0.0/16"
      public_subnet_cidrs = ["10.30.1.0/24", "10.30.2.0/24"]
      azs                 = ["eu-west-3a", "eu-west-3b"]
    }
  }
}

# Must be unique per TGW that will be peered — reusing an ASN across
# peered TGWs is a real AWS error you'll hit at apply time, not just a
# style nit.
variable "tgw_amazon_side_asn" {
  description = "Amazon-side ASN per region TGW"
  type        = map(number)
  default = {
    london  = 64512
    ireland = 64513
    paris   = 64514
  }
}

# --- Phase 2: compute ---

variable "admin_ssh_cidr" {
  description = "Your workstation's public IP in CIDR form (e.g. 203.0.113.4/32) — the only source allowed to SSH into lab nodes. Find yours with: curl -s ifconfig.me"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the public key installed on lab nodes. Same key/pattern as the Postgres homelab."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "replicaset_instance_type" {
  type    = string
  default = "t3.medium"
}
