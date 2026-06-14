# Production Notes, Gotchas & Lessons Learned

This document captures every non-obvious decision, failure mode, and hard-won
lesson encountered building this stack. Treat it as the runbook supplement that
most teams only write after an incident.

---

## 1. Infrastructure & Terraform

### Hetzner Server Types
**Gotcha:** `cx22` does not exist in `lon1` (London) or `hel1` (Helsinki).
The CX series was renamed — use `cx23` (2 vCPU, 4GB RAM) instead.
Always query available types before provisioning:
```bash
curl -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/server_types" | \
  python3 -c "import json,sys; [print(s['name'], s['cores'], s['memory']) \
  for s in json.load(sys.stdin)['server_types'] if not s['deprecation']]"
```

### SSH Key Injection
**Gotcha:** When using custom `user_data` (cloud-init) in Terraform, Hetzner
injects the SSH key into `root` but NOT into the `ubuntu` user created by
cloud-init. The ubuntu user's `authorized_keys` is empty.

**Fix:** Add this to cloud-init `runcmd`:
```yaml
runcmd:
  - cp /root/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys
  - chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
  - chmod 600 /home/ubuntu/.ssh/authorized_keys
```

### Terraform Plan Files
**Lesson:** Always save plans with `-out=tfplan` and apply from the saved plan.
Changing variables between plan and apply without saving causes unexpected
behaviour. Delete `tfplan` whenever variables change before re-planning.

### Terraform State
**Lesson:** Never commit `terraform.tfstate` to git. It contains sensitive
infrastructure details including IP addresses and resource IDs. Keep it local
or migrate to a remote backend (S3-compatible, Terraform Cloud) for team use.

### Network Zone
**Note:** Hetzner's `lon1` and `hel1` both use `eu-central` network zone for
private networks. This is not obvious from the documentation.

---

## 2. Ansible

### TTY and DEBIAN_FRONTEND
**Gotcha:** Running `apt install` over SSH without a TTY causes `FATAL ->
Failed to fork` errors from `debconf`. The package installs successfully but
Ansible reports failure.

**Fix:** Always set `DEBIAN_FRONTEND: noninteractive` in the environment for
apt tasks:
```yaml
- name: Install package
  apt:
    name: mypackage
    state: present
  environment:
    DEBIAN_FRONTEND: noninteractive
```

### group_vars Directory Structure
**Lesson:** When using Ansible vault alongside regular variables, group_vars
must be a **directory** not a file:
```
group_vars/
└── postgres_cluster/     ← directory
    ├── vars.yml          ← plain variables
    └── vault.yml         ← encrypted secrets
```
A flat `group_vars/postgres_cluster.yml` file cannot coexist with a vault file
for the same group.

### Ansible Inventory — Never Hardcode IPs
**Lesson:** Generate inventory dynamically from Terraform outputs. IPs change
on every `terraform destroy/apply`. Use `scripts/inventory/postgres.py` and
`make inventory` to always have a fresh, correct inventory.

### Task Order Matters
**Gotcha:** Ansible runs tasks in order. A task that creates a directory must
come before any task that writes files into that directory. The `conf.d`
directory for PostgreSQL must exist before deploying config files into it.

---

## 3. PostgreSQL

### PGDG Repository
**Lesson:** Always install PostgreSQL from the official PGDG apt repository,
not Ubuntu's default packages. Ubuntu 22.04 ships PostgreSQL 14 by default.
PGDG gives you version control and access to all supported versions.

### Minor Version Availability
**Gotcha:** PGDG only keeps recent minor versions available. Older minor
versions (e.g. 15.14) are removed as newer ones are released. You cannot pin
to an arbitrary historical minor version without hosting your own apt mirror
(Artifactory, Nexus etc).

### postgresql-client is a Separate Package
**Gotcha:** The `psql` binary comes from `postgresql-client-15`, not
`postgresql-15`. When downgrading minor versions, both packages must be
downgraded separately. Downgrading only `postgresql-15` leaves the old client
binary in place, causing version mismatch confusion.

### archive_mode Requires Restart
**Lesson:** `archive_mode` is a `postmaster` context parameter — it requires
a full PostgreSQL restart, not just a reload. In a Patroni cluster, use
`patronictl restart` per node, not `patronictl reload`.

### conf.d Directory
**Lesson:** PostgreSQL supports an include directory (`conf.d/`) for modular
configuration. Use it to separate concerns — put pgBackRest WAL archiving
settings in `conf.d/pgbackrest.conf` rather than polluting the main
`postgresql.conf`. Enable it by adding to `postgresql.conf`:
```
include_dir = 'conf.d'
```

---

## 4. Patroni

### etcd Must Start Before Patroni
**Lesson:** Always start etcd on all nodes and verify quorum before starting
Patroni. Patroni silently waits for etcd — if etcd isn't healthy, Patroni
won't elect a leader.

### System ID Mismatch
**Gotcha:** If PostgreSQL data directories are initialised multiple times
(e.g. after multiple `terraform destroy/apply` cycles), different system IDs
end up in etcd vs the actual clusters. Patroni logs `CRITICAL: system ID
mismatch`.

**Fix:** Wipe etcd data (`rm -rf /var/lib/etcd/*`) and PostgreSQL data
directories (`rm -rf /var/lib/postgresql/15/main/*`) on all nodes, then
restart etcd followed by Patroni simultaneously on all nodes.

### Patroni Manages PostgreSQL — Not systemd
**Lesson:** Never start/stop PostgreSQL via `systemctl start postgresql` in a
Patroni cluster. Patroni owns the PostgreSQL process. Use:
```bash
patronictl restart <cluster> <member>   # restart a node
patronictl failover <cluster>           # manual failover
patronictl switchover <cluster>         # graceful switchover
```

### patronictl edit-config Bug
**Gotcha:** `patronictl edit-config` in Patroni 3.3.2 crashes with an
`AttributeError: type object 'opts' has no attribute 'theme'` due to a ydiff
library incompatibility.

**Workaround:** Write config changes directly to etcd via etcdctl:
```bash
etcdctl --endpoints=http://10.0.1.11:2379 \
  put /db/postgres-homelab/config '{"postgresql":{"parameters":{...}}}'
```
Always verify with `patronictl show-config` after writing.

### Patroni DCS Config Survives Failover
**Lesson:** PostgreSQL parameters set via Patroni DCS (etcd) are applied to
whichever node is currently primary — they survive failover automatically.
Parameters set only in `postgresql.conf` on a specific node do NOT survive
failover if a different node becomes primary.

### Timeline Increments on Failover
**Lesson:** Every failover increments the timeline (TL). A healthy long-running
cluster on TL 10+ is normal. Timeline is critical for PITR — always note the
timeline when planning point-in-time recovery.

### Simultaneous Patroni Start Required
**Lesson:** Start Patroni on all nodes simultaneously (using `&` in bash) so
all nodes race for the leader lock at the same time. Starting them sequentially
can cause the first node to keep waiting for a leader that hasn't been elected
yet.

---

## 5. PgBouncer

### Ubuntu Package Runs as postgres User
**Gotcha:** The Ubuntu/PGDG `pgbouncer` package runs the service as the
`postgres` OS user, NOT as a dedicated `pgbouncer` user. This is different
from what the official docs imply.

**Fix:**
- Create a `pgbouncer` group
- Add `postgres` to the `pgbouncer` group
- Own config files as `postgres:pgbouncer` with mode `640`
- Own log directory as `postgres:pgbouncer` with mode `775`

### auth_dbname Required in PgBouncer 1.25
**Gotcha:** PgBouncer 1.25 introduced a breaking change — connecting to the
reserved `pgbouncer` admin database now requires `auth_dbname` to be explicitly
set. Without it you get `cannot use the reserved "pgbouncer" database as an
auth_dbname`.

**Fix:** Add to `pgbouncer.ini`:
```ini
auth_dbname = postgres
```

### scram-sha-256 vs md5 for auth_query
**Gotcha:** PgBouncer with `auth_type = scram-sha-256` cannot use plaintext
passwords in `userlist.txt` to authenticate to PostgreSQL for running
`auth_query`. The SCRAM handshake requires special handling.

**Fix:** Use `auth_type = md5` for PgBouncer's connection to PostgreSQL.
The `userlist.txt` contains the plaintext password for `pgbouncer_auth` only.
All other users are authenticated dynamically via `auth_query`.

### Least Privilege for pgbouncer_auth
**Lesson:** `pgbouncer_auth` needs only:
- `EXECUTE` on `pgbouncer.get_auth(text)` function
- `USAGE` on `pgbouncer` schema

Do NOT grant `pg_monitor`, `pg_read_all_settings`, or direct `SELECT on
pg_shadow`. Use a `SECURITY DEFINER` function to expose only what is needed:
```sql
CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename TEXT)
RETURNS TABLE(usename TEXT, passwd TEXT)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog
AS $$
  SELECT usename::TEXT, passwd::TEXT
  FROM pg_shadow WHERE usename = p_usename;
$$;
```

### userlist.txt Contains Only pgbouncer_auth
**Lesson:** In a proper setup, `userlist.txt` contains only the `pgbouncer_auth`
credentials (plaintext). All application users are authenticated dynamically
via `auth_query`. This means you never need to update `userlist.txt` when
application user passwords change.

### Transaction vs Session Pooling
**Lesson:** `pool_mode = transaction` is the enterprise standard. It allows
many more clients than connections because connections are released after each
transaction. `session` pooling holds a connection for the entire client session
and provides much less benefit. Never use `statement` pooling with PostgreSQL
(it breaks multi-statement transactions).

---

## 6. pgBackRest

### Repo Host Config vs Non-Repo Host Config
**Gotcha:** pgBackRest config differs between the repo host and other nodes:
- **Repo host (pg-01):** `repo1-path` is local, `pg1-host` points to primary
- **Other nodes:** `repo1-host` points to repo host, NO `pg1-host`

Setting both `pg1-host` and `repo1-host` as remote on the same node causes:
`ERROR [027]: pg and repo hosts cannot both be configured as remote`

### stanza-create Must Run from Repo Host
**Lesson:** Always run `stanza-create`, `backup`, `check`, and `info` commands
from the **repo host** (pg-01), not from the primary or replicas.

### archive_mode and Patroni DCS
**Lesson:** Set `archive_mode` via Patroni DCS so it survives failover:
```bash
etcdctl put /db/postgres-homelab/config '{"postgresql":{"parameters":{
  "archive_mode":"on",
  "archive_command":"pgbackrest --stanza=postgres-homelab archive-push %p"
}}}'
```
Then `patronictl restart` each node — `archive_mode` is a postmaster parameter.

### System ID Changes After Cluster Wipe
**Gotcha:** Wiping etcd and reinitialising Patroni creates a new PostgreSQL
cluster with a new system ID. The existing pgBackRest stanza is tied to the
old system ID and will refuse new backups.

**Fix:** Delete stanza data and recreate:
```bash
pgbackrest --stanza=postgres-homelab start
rm -rf /var/lib/pgbackrest/archive/postgres-homelab
rm -rf /var/lib/pgbackrest/backup/postgres-homelab
pgbackrest --stanza=postgres-homelab stanza-create
```

### Stop File Blocks stanza-create
**Gotcha:** If pgBackRest was stopped with `pgbackrest stop`, a stop file is
created. Running `stanza-create` while stopped fails with:
`ERROR [062]: stop file exists for stanza`

**Fix:** Run `pgbackrest start` before `stanza-create`.

### PITR Restore Process
**Lesson:** The correct PITR process in a Patroni cluster:
1. Stop Patroni on ALL nodes
2. Wipe data directory on the target node
3. Run `pgbackrest restore --type=time --target='...' --target-action=promote`
4. Start PostgreSQL directly via `pg_ctl` (not systemd wrapper)
5. Verify data recovery
6. Stop PostgreSQL, wipe all data directories
7. Restart etcd (wipe etcd data first if system ID changed)
8. Restart Patroni on all nodes simultaneously

### Ubuntu systemd Wrapper vs pg_ctl
**Gotcha:** `systemctl start postgresql@15-main` uses Ubuntu's wrapper which
reads cluster config from `/etc/postgresql/`. After a pgBackRest restore, this
wrapper may report `Cluster data directory is unknown` even though the data
exists. Use `pg_ctl` directly for post-restore startup:
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl \
  -D /var/lib/postgresql/15/main \
  -l /var/log/postgresql/postgresql-$(date +%Y-%m-%d).log \
  start
```

### Zstandard Compression
**Lesson:** Use `compress-type = zst` (Zstandard) not `lz4`. zst gives
enterprise-grade compression ratios (22MB → 2.7MB, 87% reduction) at speeds
comparable to lz4. It is the modern standard used by Netflix, Facebook, and
major cloud providers. pgBackRest supports it since version 2.38.

---

## 7. Security

### Never Store Secrets in Git
**Lesson:** The following must NEVER be committed:
- `terraform.tfvars` (contains infrastructure values)
- `terraform.tfstate` (contains sensitive resource details)
- `infrastructure/ansible/group_vars/postgres_cluster/vault.yml` (passwords)
- Any file containing API tokens, SSH private keys, or passwords

Use `.gitignore` to enforce this and Ansible Vault for all secrets.

### Principle of Least Privilege
**Lesson:** Every database user should have exactly the permissions needed and
nothing more:
- `pgbouncer_auth` — EXECUTE on one function only
- `pgbouncer_admin` — no PostgreSQL privileges (admin access via pgbouncer.ini)
- `replicator` — REPLICATION privilege only
- Application users — only the schemas/tables they need

### SSH Key Hygiene
**Lesson:** Generate separate SSH keys for different purposes:
- `~/.ssh/id_ed25519` — your workstation key for SSH access
- `/var/lib/postgresql/.ssh/id_ed25519` — postgres user key for pgBackRest

Never reuse keys across purposes.

### Private Network for All Internal Traffic
**Lesson:** All replication, Patroni, etcd, and pgBackRest traffic must use
the private network (10.0.1.0/24), never the public interface. Firewall rules
should restrict ports 2379, 2380, 8008 to the private network CIDR only.

---

## 8. Operational Runbook Snippets

### Check Cluster Health
```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
```

### Manual Failover
```bash
sudo -u postgres patronictl -c /etc/patroni/patroni.yml failover \
  postgres-homelab --master <current-leader> --force
```

### Check WAL Archiving
```bash
sudo -u postgres pgbackrest --stanza=postgres-homelab check
```

### Take a Differential Backup
```bash
sudo -u postgres pgbackrest --stanza=postgres-homelab \
  --type=diff backup
```

### List Available Backups
```bash
sudo -u postgres pgbackrest --stanza=postgres-homelab info
```

### Connect via PgBouncer
```bash
PGPASSWORD='...' psql -h 10.0.1.12 -p 6432 -U myuser mydb
```

### Restart Patroni Safely (one node at a time)
```bash
# Always check lag before restarting a replica
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
sudo -u postgres patronictl -c /etc/patroni/patroni.yml \
  restart postgres-homelab pg-01 --force
```

### Apply Patroni DCS Config Changes
```bash
# 1. Write to etcd
etcdctl --endpoints=http://10.0.1.11:2379 \
  put /db/postgres-homelab/config '<json>'

# 2. Verify
sudo -u postgres patronictl -c /etc/patroni/patroni.yml show-config

# 3. Restart nodes that show pending restart
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list
```

---

## 9. What This Stack Does NOT Cover (Yet)

- **Connection routing** — HAProxy or Keepalived for automatic primary/replica
  routing to PgBouncer. Currently clients must know which node is primary.
- **S3 backup repository** — pgBackRest repo is on pg-01 disk. For production,
  use S3/object storage for offsite backup redundancy.
- **TLS encryption** — etcd, Patroni REST API, and PgBouncer connections are
  unencrypted. Production should use TLS for all internal traffic.
- **Monitoring** — Prometheus + Grafana (next phase).
- **Log aggregation** — logs are local to each node. Production should ship
  to a centralised log store (ELK, Loki etc).
- **Automated failback** — after a failover, the old primary rejoins as a
  replica via pg_rewind. This is automatic in Patroni but worth testing
  explicitly.
- **Connection string management** — applications need to know the current
  primary's address. In production this is handled by HAProxy VIP, AWS RDS
  endpoint, or a service discovery mechanism.
