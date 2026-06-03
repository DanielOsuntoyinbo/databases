# Postgres Homelab — Build Status

## Infrastructure
- [x] Terraform — 3x cx23 VMs on Hetzner hel1
- [x] OS hardening — common Ansible role
- [x] PostgreSQL 15.17 — installed via PGDG repo
- [x] etcd 3.5.13 — distributed consensus store
- [x] Patroni 3.3.2 — HA orchestration, failover verified
- [x] PgBouncer 1.25.2 — connection pooling on all 3 nodes

## Current Cluster State
- pg-01: 95.217.5.118 (Replica)
- pg-02: 46.62.223.65 (Leader)
- pg-03: 46.62.223.194 (Replica)

## PgBouncer
- Pool mode: transaction
- Auth: md5 with auth_query via pgbouncer.get_auth()
- Port: 6432 on private network

## Next Steps
- [ ] pgBackRest — backup + PITR
- [ ] Prometheus + Grafana — observability
- [ ] Minor version upgrade exercise (15.17 → 15.18)
- [ ] Major version upgrade exercise (15 → 16)

## Key Facts
- SSH key: ~/.ssh/id_ed25519
- Vault password: stored in your password manager
- Private network: 10.0.1.0/24
- PostgreSQL version: 15.17
- Ansible vault: infrastructure/ansible/group_vars/postgres_cluster/vault.yml
