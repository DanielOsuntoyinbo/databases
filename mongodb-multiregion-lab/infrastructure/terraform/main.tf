# --- VPCs (one per failure domain / region) ---

module "network_london" {
  source    = "./modules/vpc"
  providers = { aws = aws.london }

  name                = "${var.project_name}-london"
  vpc_cidr            = var.regions["london"].vpc_cidr
  public_subnet_cidrs = var.regions["london"].public_subnet_cidrs
  azs                 = var.regions["london"].azs
  tags                = merge(local.common_tags, { Region = "london", FailureDomain = "A" })
}

module "network_ireland" {
  source    = "./modules/vpc"
  providers = { aws = aws.ireland }

  name                = "${var.project_name}-ireland"
  vpc_cidr            = var.regions["ireland"].vpc_cidr
  public_subnet_cidrs = var.regions["ireland"].public_subnet_cidrs
  azs                 = var.regions["ireland"].azs
  tags                = merge(local.common_tags, { Region = "ireland", FailureDomain = "B" })
}

module "network_paris" {
  source    = "./modules/vpc"
  providers = { aws = aws.paris }

  name                = "${var.project_name}-paris"
  vpc_cidr            = var.regions["paris"].vpc_cidr
  public_subnet_cidrs = var.regions["paris"].public_subnet_cidrs
  azs                 = var.regions["paris"].azs
  tags                = merge(local.common_tags, { Region = "paris", FailureDomain = "C" })
}

# --- Regional Transit Gateways ---

module "tgw_london" {
  source    = "./modules/tgw"
  providers = { aws = aws.london }

  name            = "${var.project_name}-tgw-london"
  amazon_side_asn = var.tgw_amazon_side_asn["london"]
  vpc_id          = module.network_london.vpc_id
  subnet_ids      = module.network_london.subnet_ids
  tags            = merge(local.common_tags, { Region = "london" })
}

module "tgw_ireland" {
  source    = "./modules/tgw"
  providers = { aws = aws.ireland }

  name            = "${var.project_name}-tgw-ireland"
  amazon_side_asn = var.tgw_amazon_side_asn["ireland"]
  vpc_id          = module.network_ireland.vpc_id
  subnet_ids      = module.network_ireland.subnet_ids
  tags            = merge(local.common_tags, { Region = "ireland" })
}

module "tgw_paris" {
  source    = "./modules/tgw"
  providers = { aws = aws.paris }

  name            = "${var.project_name}-tgw-paris"
  amazon_side_asn = var.tgw_amazon_side_asn["paris"]
  vpc_id          = module.network_paris.vpc_id
  subnet_ids      = module.network_paris.subnet_ids
  tags            = merge(local.common_tags, { Region = "paris" })
}

# --- Cross-region TGW peering: full mesh, 3 attachments ---

module "peering_london_ireland" {
  source = "./modules/tgw-peering"
  providers = {
    aws.requester = aws.london
    aws.accepter  = aws.ireland
  }

  name             = "${var.project_name}-peer-lon-ire"
  requester_tgw_id = module.tgw_london.tgw_id
  accepter_tgw_id  = module.tgw_ireland.tgw_id
  accepter_region  = var.regions["ireland"].aws_region
  tags             = local.common_tags
}

module "peering_ireland_paris" {
  source = "./modules/tgw-peering"
  providers = {
    aws.requester = aws.ireland
    aws.accepter  = aws.paris
  }

  name             = "${var.project_name}-peer-ire-par"
  requester_tgw_id = module.tgw_ireland.tgw_id
  accepter_tgw_id  = module.tgw_paris.tgw_id
  accepter_region  = var.regions["paris"].aws_region
  tags             = local.common_tags
}

module "peering_london_paris" {
  source = "./modules/tgw-peering"
  providers = {
    aws.requester = aws.london
    aws.accepter  = aws.paris
  }

  name             = "${var.project_name}-peer-lon-par"
  requester_tgw_id = module.tgw_london.tgw_id
  accepter_tgw_id  = module.tgw_paris.tgw_id
  accepter_region  = var.regions["paris"].aws_region
  tags             = local.common_tags
}
