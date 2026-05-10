# Firewall rules — principle of least privilege.
# Only expose what is absolutely necessary on the public interface.
# All inter-node traffic (replication, Patroni, etcd) uses the private network.

resource "hcloud_firewall" "postgres_fw" {
  name = "postgres-homelab-fw"

  labels = {
    project = "postgres-homelab"
    managed = "terraform"
  }

  # --- INBOUND RULES ---

  # SSH — required for Ansible and manual access.
  # In a real enterprise setup you'd restrict this to a bastion host IP.
  # For your homelab, restrict to your home IP if it's static:
  # source_ips = ["YOUR_HOME_IP/32"]
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "SSH access"
  }

  # PostgreSQL — only exposed for direct access during learning/debugging.
  # In production this would be locked to your application subnet only.
  # PgBouncer sits in front in the full setup.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "5432"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "PostgreSQL (restrict to app subnet in production)"
  }

  # Patroni REST API — used for health checks and cluster management.
  # Port 8008 is Patroni's default.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "8008"
    source_ips = [
      "10.0.0.0/16", # private network only
    ]
    description = "Patroni REST API (private network only)"
  }

  # etcd client port
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "2379"
    source_ips = [
      "10.0.0.0/16",
    ]
    description = "etcd client (private network only)"
  }

  # etcd peer port
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "2380"
    source_ips = [
      "10.0.0.0/16",
    ]
    description = "etcd peer communication (private network only)"
  }

  # ICMP — allows ping, useful for basic connectivity checks
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
    description = "ICMP / ping"
  }

  # --- OUTBOUND RULES ---
  # Allow all outbound — nodes need to reach apt repos, NTP etc.
  rule {
    direction   = "out"
    protocol    = "tcp"
    port        = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction   = "out"
    protocol    = "udp"
    port        = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction   = "out"
    protocol    = "icmp"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}
