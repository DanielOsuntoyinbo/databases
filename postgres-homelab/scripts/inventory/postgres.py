#!/usr/bin/env python3
"""
postgres.py — Generates Ansible inventory fragment for the Postgres cluster.

Reads Terraform JSON output from stdin and produces a structured Ansible
inventory YAML. Designed to be composable with other inventory sources
via merge.py when the infrastructure grows.

Usage:
    terraform -chdir=infrastructure/terraform/hetzner output -json | \
        python3 scripts/inventory/postgres.py

Extensibility:
    - Add new node roles by extending build_postgres_inventory()
    - Add new group vars by extending the 'vars' section
    - When multiple inventory sources exist, use scripts/inventory/merge.py
      to combine them into a single hosts.yml
"""
import json
import sys
import yaml


def parse_terraform_outputs(tf_json: dict) -> dict:
    """Extract relevant outputs from terraform JSON output."""
    return {
        "public_ips": tf_json["pg_node_public_ips"]["value"],
        "private_ips": tf_json["pg_node_private_ips"]["value"],
    }


def node_vars(name: str, public_ip: str, private_ip: str, role: str) -> dict:
    """Build per-host variables for a postgres node."""
    return {
        "ansible_host": public_ip,
        "private_ip": private_ip,
        "patroni_role": role,
    }


def build_postgres_inventory(public_ips: dict, private_ips: dict) -> dict:
    """
    Build inventory structure for postgres cluster.

    First node alphabetically becomes primary — consistent with
    Patroni bootstrap behaviour. Remaining nodes are standbys.

    To add a new role (e.g. delayed replica):
        delayed = nodes[2]
        standbys = nodes[1:2]
        # add delayed_replicas group here
    """
    nodes = sorted(public_ips.keys())
    primary = nodes[0]
    standbys = nodes[1:]

    return {
        "postgres_cluster": {
            "vars": {
                # These can be overridden per-host in host_vars/
                "postgresql_version": "15",
                "postgresql_port": 5432,
                "patroni_cluster_name": "postgres-homelab",
                "patroni_port": 8008,
                "etcd_client_port": 2379,
                "etcd_peer_port": 2380,
            },
            "children": {
                "postgres_primary": {
                    "hosts": {
                        primary: node_vars(
                            primary,
                            public_ips[primary],
                            private_ips[primary],
                            "primary"
                        )
                    }
                },
                "postgres_standbys": {
                    "hosts": {
                        node: node_vars(
                            node,
                            public_ips[node],
                            private_ips[node],
                            "standby"
                        )
                        for node in standbys
                    }
                }
            }
        }
    }


def build_inventory(public_ips: dict, private_ips: dict) -> dict:
    """
    Build the full Ansible inventory.

    Structure:
        all:
          vars:      <- global vars applied to every host
          children:
            postgres_cluster:   <- our cluster group
              children:
                postgres_primary:
                postgres_standbys:

    To add future components (monitoring, pgbouncer etc):
        inventory["all"]["children"]["monitoring"] = build_monitoring_inventory(...)
    """
    inventory = {
        "all": {
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_ed25519",
                "ansible_python_interpreter": "/usr/bin/python3",
            },
            "children": {}
        }
    }

    # Add postgres cluster — extend here for future components
    inventory["all"]["children"].update(
        build_postgres_inventory(public_ips, private_ips)
    )

    # Future components added here, e.g:
    # inventory["all"]["children"].update(build_monitoring_inventory(...))
    # inventory["all"]["children"].update(build_pgbouncer_inventory(...))

    return inventory


def main():
    try:
        tf_output = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"ERROR: Could not parse Terraform JSON output: {e}", file=sys.stderr)
        print("Make sure to run: terraform output -json | python3 scripts/inventory/postgres.py", file=sys.stderr)
        sys.exit(1)

    required_keys = ["pg_node_public_ips", "pg_node_private_ips"]
    for key in required_keys:
        if key not in tf_output:
            print(f"ERROR: Missing expected Terraform output: {key}", file=sys.stderr)
            sys.exit(1)

    parsed = parse_terraform_outputs(tf_output)
    inventory = build_inventory(parsed["public_ips"], parsed["private_ips"])

    print(yaml.dump(inventory, default_flow_style=False, sort_keys=False))


if __name__ == "__main__":
    main()
