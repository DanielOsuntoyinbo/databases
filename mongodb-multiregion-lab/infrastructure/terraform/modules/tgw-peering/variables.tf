variable "name" {
  description = "Name for this peering attachment"
  type        = string
}

variable "requester_tgw_id" {
  description = "Transit Gateway ID in the requesting region"
  type        = string
}

variable "accepter_tgw_id" {
  description = "Transit Gateway ID in the peer (accepting) region"
  type        = string
}

variable "accepter_region" {
  description = "AWS region of the peer Transit Gateway (e.g. eu-west-1)"
  type        = string
}

variable "tags" {
  description = "Tags applied to both sides of the peering attachment"
  type        = map(string)
  default     = {}
}
