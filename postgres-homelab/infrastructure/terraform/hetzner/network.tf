# Private network — all Postgres replication and Patroni traffic
# stays on this network, never exposed on public internet.
# This mirrors how enterprise setups isolate database traffic
# on a dedicated private VLAN/subnet.

resource "hcloud_network" "postgres_net" {
  name     = "postgres-private-net"
  ip_range = var.private_network_cidr

  labels = {
    project = "postgres-homelab"
    managed = "terraform"
  }
}

resource "hcloud_network_subnet" "postgres_subnet" {
  network_id   = hcloud_network.postgres_net.id
  type         = "cloud"
  network_zone = "eu-central" # lon1 uses eu-central network zone
  ip_range     = var.private_subnet_cidr
}
