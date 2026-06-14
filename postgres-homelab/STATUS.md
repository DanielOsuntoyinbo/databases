# Postgres Homelab — Build Status

## Infrastructure
- [x] Terraform — 3x cx23 VMs on Hetzner hel1 (Helsinki)
- [x] OS hardening — common Ansible role
- [x] PostgreSQL 15.17 — installed via PGDG repo
- [x] etcd 3.5.13 — distributed consensus store
- [x] Patroni 3.3.2 — HA orchestration, failover verified
- [x] PgBouncer 1.25.2 — connection pooling on all 3 nodes
- [x] pgBackRest 2.58.0 — backup + PITR verified

## Current Cluster State
- pg-01: 95.217.5.118 (Replica) — pgBackRest repo host
- pg-02: 46.62.223.65 (Leader)
- pg-03: 46.62.223.194 (Replica)

## pgBackRest Details
- Stanza: postgres-homelab
- Repo: pg-01 at /var/lib/pgbackrest
- Compression: zstandard (zst) level 3
- Retention: 2 full, 4 differential
- WAL archiving: enabled via Patroni DCS
- PITR tested: DROP TABLE recovered successfully

## Key Technical Decisions
- pgBackRest repo host config omits pg1-host (local access)
- Non-repo hosts omit repo1-host in favour of repo1-host
- archive_mode requires patronictl restart (postmaster context)
- Patroni DCS config written via etcdctl directly (patronictl edit-config has ydiff bug)
- After etcd wipe, stanza must be recreated (system-id changes)

## PgBouncer Details
- Pool mode: transaction
- Auth type: md5 with auth_query via pgbouncer.get_auth()
- Listening on: private IP port 6432
- auth_dbname = postgres required (PgBouncer 1.25 requirement)

## Next Steps
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
