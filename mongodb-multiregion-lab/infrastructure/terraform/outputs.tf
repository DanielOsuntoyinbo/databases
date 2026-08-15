output "vpc_ids" {
  value = {
    london  = module.network_london.vpc_id
    ireland = module.network_ireland.vpc_id
    paris   = module.network_paris.vpc_id
  }
}

output "vpc_cidrs" {
  value = {
    london  = module.network_london.vpc_cidr
    ireland = module.network_ireland.vpc_cidr
    paris   = module.network_paris.vpc_cidr
  }
}

output "subnet_ids" {
  value = {
    london  = module.network_london.subnet_ids
    ireland = module.network_ireland.subnet_ids
    paris   = module.network_paris.subnet_ids
  }
}

output "tgw_ids" {
  value = {
    london  = module.tgw_london.tgw_id
    ireland = module.tgw_ireland.tgw_id
    paris   = module.tgw_paris.tgw_id
  }
}

output "tgw_route_table_ids" {
  value = {
    london  = module.tgw_london.tgw_route_table_id
    ireland = module.tgw_ireland.tgw_route_table_id
    paris   = module.tgw_paris.tgw_route_table_id
  }
}

output "peering_attachment_ids" {
  value = {
    london_ireland = module.peering_london_ireland.peering_attachment_id
    ireland_paris   = module.peering_ireland_paris.peering_attachment_id
    london_paris    = module.peering_london_paris.peering_attachment_id
  }
}

output "replicaset_public_ips" {
  value = {
    london  = module.replicaset_london.public_ips
    ireland = module.replicaset_ireland.public_ips
    paris   = module.replicaset_paris.public_ips
  }
}

output "replicaset_private_ips" {
  value = {
    london  = module.replicaset_london.private_ips
    ireland = module.replicaset_ireland.private_ips
    paris   = module.replicaset_paris.private_ips
  }
}
