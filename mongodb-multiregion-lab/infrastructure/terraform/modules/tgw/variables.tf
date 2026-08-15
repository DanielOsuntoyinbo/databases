variable "name" {
  description = "Name for this regional Transit Gateway"
  type        = string
}

variable "amazon_side_asn" {
  description = "Amazon-side ASN for this TGW. Must be unique across every TGW that will be peered together."
  type        = number
}

variable "vpc_id" {
  description = "VPC to attach to this TGW"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (one per AZ) to attach to this TGW"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
