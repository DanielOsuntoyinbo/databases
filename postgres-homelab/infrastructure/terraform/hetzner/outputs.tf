# Outputs — printed to terminal after `terraform apply`.
# Also used by Ansible to build its inventory dynamically.

output "pg_node_public_ips" {
  description = "Public IPs of all Postgres nodes"
  value = {
    for i, server in hcloud_server.pg_nodes :
    server.name => server.ipv4_address
  }
}

output "pg_node_private_ips" {
  description = "Private IPs of all Postgres nodes (used for replication and Patroni)"
  value = {
    for i, server in hcloud_server.pg_nodes :
    server.name => "10.0.1.1${i + 1}"
  }
}

output "ssh_connection_strings" {
  description = "SSH commands to connect to each node"
  value = {
    for server in hcloud_server.pg_nodes :
    server.name => "ssh -i ~/.ssh/id_ed25519 ubuntu@${server.ipv4_address}"
  }
}

output "private_network_id" {
  description = "ID of the private network"
  value       = hcloud_network.postgres_net.id
}

output "ansible_inventory_hint" {
  description = "Reminder to update Ansible inventory with these IPs"
  value       = "Update infrastructure/ansible/inventory/hosts.yml with the public IPs above"
}
