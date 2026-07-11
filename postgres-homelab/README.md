# postgres-homelab

A production-grade PostgreSQL high-availability homelab built on Hetzner Cloud, fully automated with Terraform and Ansible. Designed to mirror enterprise PostgreSQL infrastructure and serve as a hands-on learning platform for database engineering skills.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Hetzner Cloud (hel1)                        │
│                  Private Network: 10.0.1.0/24                   │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │     pg-01        │  │     pg-02        │  │     pg-03        │ │
│  │  10.0.1.11       │  │  10.0.1.12       │  │  10.0.1.13       │ │
│  │                  │  │                  │  │                  │ │
│  │  PostgreSQL 15   │  │  PostgreSQL 15   │  │  PostgreSQL 15   │ │
│  │  Patroni         │◄─┤  Patroni         ├─►│  Patroni         │ │
│  │  etcd            │  │  etcd (Leader)   │  │  etcd            │ │
│  │  PgBouncer       │  │  PgBouncer       │  │  PgBouncer       │ │
│  │  pgBackRest repo │  │  pgBackRest      │  │  pgBackRest      │ │
│  │  Prometheus      │  │                  │  │                  │ │
│  │  Grafana         │  │                  │  │                  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Stack

| Component | Version | Role |
|---|---|---|
| PostgreSQL | 15.17 | Database engine |
| Patroni | 3.3.2 | HA orchestration + automatic failover |
| etcd | 3.5.13 | Distributed consensus store |
| PgBouncer | 1.25.2 | Connection pooling (transaction mode) |
| pgBackRest | 2.58.0 | Physical backup + WAL archiving + PITR |
| Prometheus | 2.51.0 | Metrics collection |
| Grafana | 13.1.0 | Dashboards + alerting |
| node_exporter | 1.7.0 | OS metrics |
| postgres_exporter | 0.15.0 | PostgreSQL metrics |
| Terraform | ≥ 1.5.0 | Infrastructure provisioning |
| Ansible | 2.16.x | Configuration management |

## Infrastructure

3x Hetzner cx23 VMs (2 vCPU, 4GB RAM, 40GB SSD) in Helsinki (hel1):

| Node | Public IP | Private IP | Roles |
|---|---|---|---|
| pg-01 | 95.217.5.118 | 10.0.1.11 | Replica, pgBackRest repo, Monitoring |
| pg-02 | 46.62.223.65 | 10.0.1.12 | **Leader** (current primary) |
| pg-03 | 46.62.223.194 | 10.0.1.13 | Replica |

## Repository Structure

```
postgres-homelab/
├── Makefile                          # Orchestration commands
├── ansible.cfg                       # Ansible configuration
├── STATUS.md                         # Current build status
├── docs/
│   └── PRODUCTION_NOTES.md           # Gotchas, lessons, runbooks
├── scripts/
│   └── inventory/
│       ├── postgres.py               # Dynamic inventory from Terraform
│       └── merge.py                  # Future: multi-component inventory
└── infrastructure/
    ├── terraform/
    │   └── hetzner/
    │       ├── main.tf               # Provider config
    │       ├── servers.tf            # VM definitions
    │       ├── network.tf            # Private network
    │       ├── firewall.tf           # Security rules
    │       ├── variables.tf          # Input variables
    │       ├── outputs.tf            # IPs and connection strings
    │       ├── ssh.tf                # SSH key reference
    │       └── terraform.tfvars.example
    └── ansible/
        ├── site.yml                  # Master playbook
        ├── group_vars/
        │   └── postgres_cluster/
        │       ├── vars.yml          # Cluster variables
        │       └── vault.yml         # Encrypted secrets (git ignored)
        └── roles/
            ├── common/               # OS hardening, NTP, sysctl
            ├── postgres/             # PostgreSQL install + config
            ├── etcd/                 # etcd install + config
            ├── patroni/              # Patroni HA setup
            ├── pgbouncer/            # Connection pooling
            ├── pgbackrest/           # Backup + PITR
            └── monitoring/           # Prometheus + Grafana stack
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) ≥ 2.16
- [Hetzner Cloud](https://hetzner.com/cloud) account with API token
- SSH key pair

## Quick Start

### 1. Clone the repository

```bash
git clone git@github.com:DanielOsuntoyinbo/databases.git
cd databases/postgres-homelab
```

### 2. Configure environment

```bash
# Set Hetzner API token
export HCLOUD_TOKEN="your-token-here"
echo 'export HCLOUD_TOKEN="your-token-here"' >> ~/.bashrc

# Copy and edit Terraform variables
cp infrastructure/terraform/hetzner/terraform.tfvars.example \
   infrastructure/terraform/hetzner/terraform.tfvars

# Edit with your SSH key name from Hetzner console
nano infrastructure/terraform/hetzner/terraform.tfvars
```

### 3. Provision infrastructure

```bash
cd infrastructure/terraform/hetzner
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Generate Ansible inventory

```bash
cd ../../..   # back to postgres-homelab/
make inventory
```

### 5. Create Ansible vault

```bash
ansible-vault create infrastructure/ansible/group_vars/postgres_cluster/vault.yml
```

Add the following secrets:
```yaml
vault_replication_password: "your-strong-password"
vault_postgres_superuser_password: "your-strong-password"
vault_pgbouncer_auth_password: "your-strong-password"
vault_pgbouncer_admin_password: "your-strong-password"
vault_postgres_exporter_password: "your-strong-password"
vault_grafana_admin_password: "your-strong-password"
vault_grafana_secret_key: "your-32-char-random-string"
```

### 6. Test connectivity

```bash
make ping
```

### 7. Provision all nodes

```bash
ansible-playbook -i infrastructure/ansible/inventory/hosts.yml \
  infrastructure/ansible/site.yml \
  --ask-vault-pass
```

### 8. Initialise pgBackRest stanza

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<pg-01-ip> \
  "sudo -u postgres pgbackrest --stanza=postgres-homelab stanza-create"
```

### 9. Take first backup

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<pg-01-ip> \
  "sudo -u postgres pgbackrest --stanza=postgres-homelab --type=full backup"
```

## Make Commands

```bash
make inventory       # Generate Ansible inventory from Terraform outputs
make ping            # Test Ansible connectivity to all nodes
make provision       # Run full Ansible provisioning
make apply-infra     # Provision VMs + generate inventory + ping
make destroy-infra   # Destroy all Hetzner VMs (careful!)
make ssh-pg01        # SSH into pg-01
make ssh-pg02        # SSH into pg-02
make ssh-pg03        # SSH into pg-03
make clean           # Remove generated files
```

## Operational Runbooks

### Check cluster health

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<any-node-ip> \
  "sudo -u postgres patronictl -c /etc/patroni/patroni.yml list"
```

Expected output:
```
+ Cluster: postgres-homelab ----+----+-----------+
| Member | Host      | Role    | State     | TL | Lag in MB |
+--------+-----------+---------+-----------+----+-----------+
| pg-01  | 10.0.1.11 | Replica | streaming |  1 |         0 |
| pg-02  | 10.0.1.12 | Leader  | running   |  1 |           |
| pg-03  | 10.0.1.13 | Replica | streaming |  1 |         0 |
+--------+-----------+---------+-----------+----+-----------+
```

### Manual failover

```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml \
  failover postgres-homelab --master pg-02 --force
```

### Connect via PgBouncer

```bash
# Connect to primary via PgBouncer
psql -h 10.0.1.12 -p 6432 -U myuser mydb
```

### Take a differential backup

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<pg-01-ip> \
  "sudo -u postgres pgbackrest --stanza=postgres-homelab --type=diff backup"
```

### List available backups

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<pg-01-ip> \
  "sudo -u postgres pgbackrest --stanza=postgres-homelab info"
```

### Point-in-time recovery (PITR)

```bash
# 1. Stop Patroni on all nodes
for ip in <pg-01> <pg-02> <pg-03>; do
  ssh ubuntu@$ip "sudo systemctl stop patroni"
done

# 2. Restore to target time on primary node
ssh ubuntu@<pg-02> "
  sudo -u postgres find /var/lib/postgresql/15/main -mindepth 1 -delete
  sudo -u postgres pgbackrest --stanza=postgres-homelab \
    --type=time \
    --target='2026-01-01 12:00:00+00' \
    --target-action=promote \
    restore
  sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl \
    -D /var/lib/postgresql/15/main start
"

# 3. Verify data recovery, then restart cluster normally
```

### Access Grafana

```bash
# Create SSH tunnel
ssh -i ~/.ssh/id_ed25519 -L 3000:10.0.1.11:3000 ubuntu@<pg-01-ip> -N &

# Open browser
open http://localhost:3000
# Login: admin / <vault_grafana_admin_password>
```

### Access Prometheus

```bash
ssh -i ~/.ssh/id_ed25519 -L 9090:10.0.1.11:9090 ubuntu@<pg-01-ip> -N &
open http://localhost:9090
```

## Monitoring

Prometheus scrapes metrics from all 3 nodes every 15 seconds:

| Exporter | Port | Metrics |
|---|---|---|
| node_exporter | 9100 | CPU, RAM, disk, network |
| postgres_exporter | 9187 | Connections, replication lag, queries, locks |
| Patroni REST API | 8008 | Leader status, cluster health |

### Grafana Dashboards

| Dashboard | ID | Purpose |
|---|---|---|
| Node Exporter Full | 1860 | OS metrics |
| PostgreSQL Database | 9628 | Database metrics |
| Patroni | 18870 | HA cluster status |

### Alerting Rules

- PostgreSQL down
- No Patroni leader
- Replication lag > 100MB (warning) / 500MB (critical)
- Connections > 80% of max_connections
- Disk space < 20% (warning) / 10% (critical)
- Long running queries > 5 minutes
- Deadlocks detected
- High CPU > 90%
- High memory > 90%

## Security

- SSH key authentication only (password auth disabled)
- All replication, Patroni, etcd traffic on private network only
- Firewall restricts ports 2379, 2380, 8008 to private network CIDR
- Ansible Vault encrypts all secrets
- PgBouncer uses security definer function for auth_query (least privilege)
- `pgbouncer_auth` has EXECUTE on one function only

## What's Not Covered (Future Work)

- **HAProxy** — automatic primary/replica routing with VIP
- **TLS** — encrypt etcd, Patroni REST API, and PgBouncer connections
- **S3 backup repository** — offsite pgBackRest storage
- **Log aggregation** — centralised logging (Loki/ELK)
- **Major version upgrades** — 15 → 16 → 17 → 18 exercises

## Documentation

- [STATUS.md](STATUS.md) — current build state
- [docs/PRODUCTION_NOTES.md](docs/PRODUCTION_NOTES.md) — gotchas, lessons learned, production runbooks

## License

MIT
