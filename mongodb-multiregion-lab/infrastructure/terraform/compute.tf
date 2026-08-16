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
