# databases

A collection of enterprise-grade database homelab projects built on cloud infrastructure,
fully automated with Infrastructure as Code. Each project mirrors real production database
engineering patterns and serves as a deliberate learning platform.

## Projects

| Project | Status | Description |
|---|---|---|
| [postgres-homelab](./postgres-homelab) | ✅ Complete | PostgreSQL HA cluster with Patroni, PgBouncer, pgBackRest and full observability |
| mongodb-homelab | 🔜 Planned | MongoDB replica sets and sharding |
| clickhouse-homelab | 🔜 Planned | ClickHouse OLAP cluster |
| mysql-homelab | 🔜 Planned | MySQL InnoDB Cluster |
| mariadb-homelab | 🔜 Planned | MariaDB Galera Cluster |
| cassandra-homelab | 🔜 Planned | Apache Cassandra multi-node |
| sqlserver-homelab | 🔜 Planned | SQL Server Always On AG |

## Engineering Principles

Every project in this repo follows the same core principles regardless of the database technology:

- **Infrastructure as Code** — reproducible, version-controlled infrastructure
- **High Availability** — multi-node clusters with automatic failover
- **Backup & Recovery** — point-in-time recovery tested and documented
- **Observability** — metrics, dashboards and alerting
- **Security** — least privilege, encrypted secrets, private networking
- **Documentation** — production runbooks and lessons learned

## About

Built as a deliberate skills development platform for enterprise database
and infrastructure engineering. Each project is designed to transfer directly
to production environments.
