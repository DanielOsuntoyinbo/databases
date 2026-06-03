# Postgres Homelab — Build Status

## Infrastructure
- [x] Terraform — 3x cx23 VMs on Hetzner hel1 (Helsinki)
- [x] OS hardening — common Ansible role
- [x] PostgreSQL 15.17 — installed via PGDG repo
- [x] etcd 3.5.13 — distributed consensus store
- [x] Patroni 3.3.2 — HA orchestration, failover verified
- [x] PgBouncer 1.25.2 — connection pooling on all 3 nodes

## Current Cluster State
- pg-01: 95.217.5.118 (Replica)
- pg-02: 46.62.223.65 (Leader)
- pg-03: 46.62.223.194 (Replica)

## PgBouncer Details
- Pool mode: transaction
- Auth type: md5 with auth_query via pgbouncer.get_auth()
- Listening on: private IP port 6432
- userlist.txt contains only pgbouncer_auth (plaintext)
- All other users authenticated dynamically via auth_query
- pgbouncer_auth has EXECUTE on pgbouncer.get_auth() function only

## Key Technical Decisions
- Server type: cx22 doesn't exist in hel1 — use cx23
- Ubuntu pgbouncer package runs as postgres user not pgbouncer user
- postgres user added to pgbouncer group for file access
- auth_dbname = postgres required in pgbouncer.ini (PgBouncer 1.25 requirement)
- scram-sha-256 caused issues with auth_query — using md5 instead
- pg_hba.conf: 10.0.0.0/16 allowed with scram-sha-256 for app connections

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
- Repo: github.com/DanielOsuntoyinbo/databases (postgres-homelab subdirectory)
- Make commands: make inventory, make ping, make provision
