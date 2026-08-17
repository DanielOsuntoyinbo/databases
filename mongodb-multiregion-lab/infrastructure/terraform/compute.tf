locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # mongod ingress: every replica set member needs to reach every
  # other member on 27017 — same-region peers (local VPC CIDR) and
  # both other regions (peer VPC CIDRs). This is the same 3-CIDR list
  # in all three regions' security groups by design.
  all_vpc_cidrs = [
    var.regions["london"].vpc_cidr,
    var.regions["ireland"].vpc_cidr,
    var.regions["paris"].vpc_cidr,
  ]
}

# --- Unsharded replica set: 1 voting member per region (slides 13-26) ---

module "replicaset_london" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-london"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[0]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A" })
}

module "replicaset_ireland" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-ireland"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[0]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B" })
}

module "replicaset_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                 = "${var.project_name}-paris"
  vpc_id               = module.network_paris.vpc_id
  subnet_id            = module.network_paris.subnet_ids[0]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "paris", FailureDomain = "C" })
}

# --- 2+2+1 topology extension: second data-bearing node per region
# for London and Ireland (slide 8/10, 19; docs/00-lab-architecture-and-build-plan.md
# section 10). Separate module calls, not node_count bumps on the
# existing ones — avoids Terraform wanting to touch the already-live,
# already-bootstrapped instances. Second subnet (different AZ) for
# genuine within-region multi-AZ spread. These are NOT added to the
# replica set by Terraform/Ansible — that's a deliberate manual
# rs.add() step during the actual demo, same reasoning as the arbiter.

module "replicaset_london_2" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-london-2"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[1]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A" })
}

module "replicaset_ireland_2" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-ireland-2"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[1]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B" })
}

# --- Region-majority anti-pattern test: a third Ireland node, giving
# Ireland an outright majority (3 of 5 total votes) by itself. Point:
# odd total vote count alone isn't sufficient — if any single failure
# domain holds a majority on its own, that domain's outage takes the
# whole cluster's write availability with it, exactly like an even
# vote count does, just via a different mechanism. Reuses subnet[0]
# (AZ diversity isn't the point of this specific test).
module "replicaset_ireland_3" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-ireland-3"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[0]
  node_role            = "replicaset"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B" })
}

# --- Arbiter: standalone instance, dedicated (slide 26) ---
#
# Deliberately NOT co-located on an existing node. An arbiter is just a
# regular mongod process — there's no special "arbiter mode" in
# mongod.conf, arbiter status is purely a replica-set-config-level
# distinction (rs.addArb()). A dedicated instance reuses this same
# ec2-fleet module and the standard psmdb role unchanged: standard port
# 27017, standard systemd unit, no custom PID-file/port work needed.
# Small instance type since an arbiter needs almost no resources —
# cost difference vs co-locating is negligible, and a separate host
# with its own hostname is far clearer evidence for a live talk than
# two mongod processes sharing one box on different ports.
module "arbiter_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                 = "${var.project_name}-paris-arbiter"
  vpc_id               = module.network_paris.vpc_id
  subnet_id            = module.network_paris.subnet_ids[1]
  node_role            = "arbiter"
  node_count           = 1
  instance_type        = "t3.micro"
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "paris", FailureDomain = "C", Role = "arbiter" })
}

# --- Multi-AZ comparison topology: 3 nodes, all within London, spread
# across its 2 AZs. Entirely separate replica set (psmdb-multiaz-lab),
# independent of the main multi-region cluster. Purpose: same
# write-concern/latency benchmark methodology as Phase 3, run against
# this topology instead — real measured cross-AZ latency (<2ms
# expected) vs the already-measured cross-region latency (9-11ms),
# side by side. Local VPC CIDR only for ingress — no cross-region
# traffic needed for a single-region topology.

module "multiaz_1" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-multiaz-1"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[0]
  node_role            = "multiaz"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = [var.regions["london"].vpc_cidr]
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "multiaz" })
}

module "multiaz_2" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-multiaz-2"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[1]
  node_role            = "multiaz"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = [var.regions["london"].vpc_cidr]
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "multiaz" })
}

module "multiaz_3" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-multiaz-3"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[2]
  node_role            = "multiaz"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = [var.regions["london"].vpc_cidr]
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "multiaz" })
}

# --- Phase 5: sharded cluster (slides 34-37) ---
# Trimmed scope per the original build plan: CSRS + 1 shard, both
# spread 1-per-region for the same resilience story as the main
# replica set. mongos routers are a different binary (not mongod) —
# smaller instance type since they're stateless.

module "configsvr_london" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-configsvr-london"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[0]
  node_role            = "configsvr"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "configsvr" })
}

module "configsvr_ireland" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-configsvr-ireland"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[0]
  node_role            = "configsvr"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B", Role = "configsvr" })
}

module "configsvr_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                 = "${var.project_name}-configsvr-paris"
  vpc_id               = module.network_paris.vpc_id
  subnet_id            = module.network_paris.subnet_ids[0]
  node_role            = "configsvr"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "paris", FailureDomain = "C", Role = "configsvr" })
}

module "shard1_london" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-shard1-london"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[1]
  node_role            = "shard1"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "shard1" })
}

module "shard1_ireland" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-shard1-ireland"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[1]
  node_role            = "shard1"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B", Role = "shard1" })
}

module "shard1_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                 = "${var.project_name}-shard1-paris"
  vpc_id               = module.network_paris.vpc_id
  subnet_id            = module.network_paris.subnet_ids[1]
  node_role            = "shard1"
  node_count           = 1
  instance_type        = var.replicaset_instance_type
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "paris", FailureDomain = "C", Role = "shard1" })
}

module "mongos_london" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.london }

  name                 = "${var.project_name}-mongos-london"
  vpc_id               = module.network_london.vpc_id
  subnet_id            = module.network_london.subnet_ids[0]
  node_role            = "mongos"
  node_count           = 1
  instance_type        = "t3.small"
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "london", FailureDomain = "A", Role = "mongos" })
}

module "mongos_ireland" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                 = "${var.project_name}-mongos-ireland"
  vpc_id               = module.network_ireland.vpc_id
  subnet_id            = module.network_ireland.subnet_ids[0]
  node_role            = "mongos"
  node_count           = 1
  instance_type        = "t3.small"
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "ireland", FailureDomain = "B", Role = "mongos" })
}

module "mongos_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                 = "${var.project_name}-mongos-paris"
  vpc_id               = module.network_paris.vpc_id
  subnet_id            = module.network_paris.subnet_ids[0]
  node_role            = "mongos"
  node_count           = 1
  instance_type        = "t3.small"
  ssh_public_key       = local.ssh_public_key
  admin_ssh_cidr       = var.admin_ssh_cidr
  mongod_ingress_cidrs = local.all_vpc_cidrs
  tags                 = merge(local.common_tags, { Region = "paris", FailureDomain = "C", Role = "mongos" })
}
