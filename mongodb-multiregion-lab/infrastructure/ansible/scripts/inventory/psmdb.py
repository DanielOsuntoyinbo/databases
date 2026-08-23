#!/usr/bin/env python3
"""
Generates infrastructure/ansible/inventory/hosts.yml from Terraform
outputs. Run via `make inventory` from the repo root — same pattern as
the Postgres homelab's scripts/inventory/postgres.py.

Assumes one replica set node per region for now (Topology A). Extend
the REGIONS list / priority map here when Topology B (multi-AZ) or
additional roles (configsvr/shard/mongos) get added in later phases.
"""

import json
import subprocess
import sys
from pathlib import Path

TERRAFORM_DIR = Path(__file__).resolve().parents[3] / "terraform"
INVENTORY_OUT = Path(__file__).resolve().parents[2] / "inventory" / "hosts.yml"

# London preferred as primary (highest priority), matching the talk's
# slide 21 "where do we prefer the primary" story.
REGIONS = {
    "london":  {"priority": 3, "member_id": 0},
    "ireland": {"priority": 2, "member_id": 1},
    "paris":   {"priority": 1, "member_id": 2},
}


def terraform_output() -> dict:
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def build_inventory(tf_out: dict) -> dict:
    public_ips = tf_out["replicaset_public_ips"]["value"]
    private_ips = tf_out["replicaset_private_ips"]["value"]

    region_groups = {}
    all_hosts = {}

    for region, cfg in REGIONS.items():
        # Skip regions that weren't provisioned this run (scoped/
        # partial deployments — e.g. a test that only needs London +
        # Ireland). public_ips[region] is None if that module's
        # output couldn't be evaluated (module never applied).
        if public_ips.get(region) is None or private_ips.get(region) is None:
            continue

        hostname = f"psmdb-{region}-replicaset-1"
        public_ip = public_ips[region][0]
        private_ip = private_ips[region][0]

        all_hosts[hostname] = {
            "ansible_host": public_ip,
            "private_ip": private_ip,
            "region": region,
            "psmdb_alias": f"psmdb-{region}",
            "replicaset_member_id": cfg["member_id"],
            "replicaset_priority": cfg["priority"],
        }
        region_groups[f"region_{region}"] = {"hosts": {hostname: None}}

    inventory = {
        "all": {
            "children": {
                "replicaset": {
                    "children": region_groups,
                },
            },
        },
    }

    # Flatten host vars into the top-level structure ansible expects
    for region_key, group in region_groups.items():
        hostname = next(iter(group["hosts"]))
        group["hosts"][hostname] = all_hosts[hostname]

    # Arbiter: standalone instance, own group, not part of the
    # "replicaset" group's initial rs.initiate() member set — it gets
    # added later via rs.addArb() as a deliberate, separate step.
    if tf_out.get("arbiter_public_ip", {}).get("value") is not None and tf_out.get("arbiter_private_ip", {}).get("value") is not None:
        arbiter_hostname = "psmdb-paris-arbiter-1"
        inventory["all"]["children"]["arbiter"] = {
            "hosts": {
                arbiter_hostname: {
                    "ansible_host": tf_out["arbiter_public_ip"]["value"],
                    "private_ip": tf_out["arbiter_private_ip"]["value"],
                    "region": "paris",
                    "psmdb_alias": "psmdb-paris-arbiter",
                }
            }
        }

    # 2+2+1 extension: second data-bearing node per region. Kept in a
    # separate group from "replicaset" — that group's tasks include
    # the fresh-cluster rs.initiate() bootstrap logic, which should
    # never run against these (already-bootstrapped cluster, these
    # join later via a manual rs.add()).
    extra_nodes = {
        "london_2": "london",
        "ireland_2": "ireland",
        "ireland_3": "ireland",
    }
    extra_hosts = {}
    for key, region in extra_nodes.items():
        pub_key, priv_key = f"{key}_public_ip", f"{key}_private_ip"
        pub_val = tf_out.get(pub_key, {}).get("value")
        priv_val = tf_out.get(priv_key, {}).get("value")
        if pub_val is not None and priv_val is not None:
            hostname = f"psmdb-{key.replace('_', '-')}-replicaset-1"
            extra_hosts[hostname] = {
                "ansible_host": pub_val,
                "private_ip": priv_val,
                "region": region,
                "psmdb_alias": f"psmdb-{key.replace('_', '-')}",
            }
    if extra_hosts:
        inventory["all"]["children"]["extra_replicaset"] = {"hosts": extra_hosts}

    # Multi-AZ comparison topology — entirely separate replica set,
    # 3 nodes all in London. Own group, own group_vars override
    # (psmdb_replset_name), own bootstrap play.
    multiaz_pub = tf_out.get("multiaz_public_ips", {}).get("value") or {}
    multiaz_priv = tf_out.get("multiaz_private_ips", {}).get("value") or {}
    multiaz_hosts = {}
    for key in ("multiaz_1", "multiaz_2", "multiaz_3"):
        if multiaz_pub.get(key) is not None and multiaz_priv.get(key) is not None:
            alias = key.replace("_", "-")
            hostname = f"psmdb-{alias}-1"
            multiaz_hosts[hostname] = {
                "ansible_host": multiaz_pub[key],
                "private_ip": multiaz_priv[key],
                "region": "london",
                "psmdb_alias": f"psmdb-{alias}",
            }
    if multiaz_hosts:
        inventory["all"]["children"]["multiaz"] = {"hosts": multiaz_hosts}

    # Sharded cluster: CSRS, shard1, mongos — each a region-tagged
    # trio, matching the main replica set's failure-domain pattern.
    sharding_groups = {
        "configsvr": "configsvr_public_ips",
        "shard1": "shard1_public_ips",
        "mongos": "mongos_public_ips",
    }
    for group_name, pub_key in sharding_groups.items():
        priv_key = pub_key.replace("public", "private")
        pub_ips = tf_out.get(pub_key, {}).get("value") or {}
        priv_ips = tf_out.get(priv_key, {}).get("value") or {}
        group_hosts = {}
        for region in ("london", "ireland", "paris"):
            if pub_ips.get(region) is not None and priv_ips.get(region) is not None:
                hostname = f"psmdb-{group_name}-{region}-1"
                group_hosts[hostname] = {
                    "ansible_host": pub_ips[region],
                    "private_ip": priv_ips[region],
                    "region": region,
                    "psmdb_alias": f"psmdb-{group_name}-{region}",
                }
        if group_hosts:
            inventory["all"]["children"][group_name] = {"hosts": group_hosts}

    return inventory


def to_yaml(data: dict) -> str:
    # Minimal hand-rolled YAML emitter so this script has no
    # dependency beyond the standard library — avoids requiring
    # pyyaml just to generate a small inventory file.
    import yaml  # noqa: local import, fall back below if unavailable
    return yaml.safe_dump(data, sort_keys=False, default_flow_style=False)


def main():
    tf_out = terraform_output()

    required = ("replicaset_public_ips", "replicaset_private_ips")
    missing = [k for k in required if k not in tf_out]
    if missing:
        print(f"Missing Terraform outputs: {missing}. Run 'terraform apply' first.", file=sys.stderr)
        sys.exit(1)

    inventory = build_inventory(tf_out)

    INVENTORY_OUT.parent.mkdir(parents=True, exist_ok=True)
    try:
        INVENTORY_OUT.write_text(to_yaml(inventory))
    except ModuleNotFoundError:
        print("pyyaml not installed. Run: pip install pyyaml --break-system-packages", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote inventory to {INVENTORY_OUT}")


if __name__ == "__main__":
    main()
