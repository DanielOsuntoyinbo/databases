# terraform.tfvars — your actual variable values.
# THIS FILE IS GIT IGNORED — never commit it.
# See terraform.tfvars.example for the template.

location             = "lon1"
server_type          = "cx22"
os_image             = "ubuntu-22.04"
ssh_key_name         = "postgres-homelab"   # must match the name in Hetzner console exactly
postgres_node_count  = 3
private_network_cidr = "10.0.0.0/16"
private_subnet_cidr  = "10.0.1.0/24"
