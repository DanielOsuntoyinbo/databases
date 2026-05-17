# Postgres nodes — pg-01, pg-02, pg-03
# pg-01 will become primary, pg-02 and pg-03 standbys.
# Patroni manages which node is actually primary at runtime —
# so all three are provisioned identically here. No node is
# hardcoded as primary at the infrastructure level.

resource "hcloud_server" "pg_nodes" {
  count       = var.postgres_node_count
  name        = "pg-0${count.index + 1}"
  server_type = var.server_type
  image       = var.os_image
  location    = var.location

  ssh_keys = [tostring(data.hcloud_ssh_key.default.id)]

  firewall_ids = [hcloud_firewall.postgres_fw.id]

  # Assign a static private IP to each node.
  # These IPs are what Patroni and pgBackRest configs will reference.
  # 10.0.1.11 = pg-01, 10.0.1.12 = pg-02, 10.0.1.13 = pg-03
  network {
    network_id = hcloud_network.postgres_net.id
    ip         = "10.0.1.1${count.index + 1}"
  }

  # Cloud-init — baseline hardening applied to every node on first boot.
  # Keeps the Ansible playbooks focused on Postgres, not OS setup.
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - ca-certificates
      - gnupg
      - python3
      - python3-pip
      - vim
      - htop
      - net-tools
      - dnsutils

    # Create a dedicated postgres system user consistent with
    # what the postgresql apt package will also expect.
    users:
      - name: ubuntu
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL

    # Disable password auth — SSH key only.
    # This is non-negotiable in any production environment.
    runcmd:
      - mkdir -p /home/ubuntu/.ssh
      - cp /root/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys
      - chown -R ubuntu:ubuntu /home/ubuntu/.ssh
      - chmod 700 /home/ubuntu/.ssh
      - chmod 600 /home/ubuntu/.ssh/authorized_keys
      - sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      - sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      - systemctl restart sshd
      - timedatectl set-timezone UTC
  EOF

  labels = {
    project = "postgres-homelab"
    role    = "postgres"
    index   = tostring(count.index + 1)
    managed = "terraform"
  }

  # Ensure network is ready before servers are considered provisioned
  depends_on = [hcloud_network_subnet.postgres_subnet]
}

# Attach firewall explicitly to each server
# (belt-and-suspenders alongside the firewall_ids in the server resource)
resource "hcloud_firewall_attachment" "pg_nodes_fw" {
  firewall_id = hcloud_firewall.postgres_fw.id
  server_ids  = [for s in hcloud_server.pg_nodes : s.id]
}
