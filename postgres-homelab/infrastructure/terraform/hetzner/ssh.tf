# Reference the SSH key you added manually in the Hetzner console.
# We use a data source (lookup) rather than a resource (create) because
# you already added the key via the UI — Terraform just needs to find it.

data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
}
