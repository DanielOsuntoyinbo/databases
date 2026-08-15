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

  name                  = "${var.project_name}-london"
  vpc_id                = module.network_london.vpc_id
  subnet_id             = module.network_london.subnet_ids[0]
  node_role             = "replicaset"
  node_count            = 1
  instance_type         = var.replicaset_instance_type
  ssh_public_key        = local.ssh_public_key
  admin_ssh_cidr        = var.admin_ssh_cidr
  mongod_ingress_cidrs  = local.all_vpc_cidrs
  tags                  = merge(local.common_tags, { Region = "london", FailureDomain = "A" })
}

module "replicaset_ireland" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.ireland }

  name                  = "${var.project_name}-ireland"
  vpc_id                = module.network_ireland.vpc_id
  subnet_id             = module.network_ireland.subnet_ids[0]
  node_role             = "replicaset"
  node_count            = 1
  instance_type         = var.replicaset_instance_type
  ssh_public_key        = local.ssh_public_key
  admin_ssh_cidr        = var.admin_ssh_cidr
  mongod_ingress_cidrs  = local.all_vpc_cidrs
  tags                  = merge(local.common_tags, { Region = "ireland", FailureDomain = "B" })
}

module "replicaset_paris" {
  source    = "./modules/ec2-fleet"
  providers = { aws = aws.paris }

  name                  = "${var.project_name}-paris"
  vpc_id                = module.network_paris.vpc_id
  subnet_id             = module.network_paris.subnet_ids[0]
  node_role             = "replicaset"
  node_count            = 1
  instance_type         = var.replicaset_instance_type
  ssh_public_key        = local.ssh_public_key
  admin_ssh_cidr        = var.admin_ssh_cidr
  mongod_ingress_cidrs  = local.all_vpc_cidrs
  tags                  = merge(local.common_tags, { Region = "paris", FailureDomain = "C" })
}
