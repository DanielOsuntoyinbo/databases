variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "lon1"
}

variable "server_type" {
  description = "Hetzner server type for Postgres nodes"
  type        = string
  default     = "cx22" # 2 vCPU, 4GB RAM — cheapest viable for Postgres
}

variable "os_image" {
  description = "OS image for all VMs"
  type        = string
  default     = "ubuntu-22.04"
}

variable "ssh_key_name" {
  description = "Name of the SSH key added to your Hetzner project"
  type        = string
}

variable "postgres_node_count" {
  description = "Number of Postgres nodes (3 = 1 primary + 2 standbys)"
  type        = number
  default     = 3
}

variable "private_network_cidr" {
  description = "CIDR for the private network between nodes"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}
