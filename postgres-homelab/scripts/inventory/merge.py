#!/usr/bin/env python3
"""
merge.py — Merges multiple Ansible inventory fragments into one hosts.yml.

NOT NEEDED YET — stubbed out for future use when multiple infrastructure
components exist (monitoring, pgbouncer, bastion etc).

Future usage:
    python3 scripts/inventory/merge.py \
        <(terraform -chdir=infrastructure/terraform/hetzner output -json | python3 scripts/inventory/postgres.py) \
        <(terraform -chdir=infrastructure/terraform/monitoring output -json | python3 scripts/inventory/monitoring.py) \
        > infrastructure/ansible/inventory/hosts.yml

To activate:
    1. Create additional inventory generators (monitoring.py, pgbouncer.py etc)
    2. Update Makefile 'inventory' target to use this script
    3. Implement deep_merge() below
"""
import sys
import yaml


def deep_merge(base: dict, override: dict) -> dict:
    """
    Deep merge two inventory dicts.
    Override values take precedence over base values.
    Lists are concatenated, dicts are recursively merged.

    TODO: implement when needed
    """
    raise NotImplementedError(
        "merge.py is not yet implemented. "
        "Add this when you have multiple inventory sources."
    )


def main():
    # TODO: read multiple YAML files from argv and deep merge them
    print("merge.py not yet implemented", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
