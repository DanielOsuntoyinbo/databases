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
    london  = try(module.replicaset_london.public_ips, null)
    ireland = try(module.replicaset_ireland.public_ips, null)
    paris   = try(module.replicaset_paris.public_ips, null)
  }
}

output "replicaset_private_ips" {
  value = {
    london  = try(module.replicaset_london.private_ips, null)
    ireland = try(module.replicaset_ireland.private_ips, null)
    paris   = try(module.replicaset_paris.private_ips, null)
  }
}

output "arbiter_public_ip" {
  value = try(module.arbiter_paris.public_ips[0], null)
}

output "arbiter_private_ip" {
  value = try(module.arbiter_paris.private_ips[0], null)
}

output "london_2_public_ip" {
  value = try(module.replicaset_london_2.public_ips[0], null)
}

output "london_2_private_ip" {
  value = try(module.replicaset_london_2.private_ips[0], null)
}

output "ireland_2_public_ip" {
  value = try(module.replicaset_ireland_2.public_ips[0], null)
}

output "ireland_2_private_ip" {
  value = try(module.replicaset_ireland_2.private_ips[0], null)
}

output "ireland_3_public_ip" {
  value = try(module.replicaset_ireland_3.public_ips[0], null)
}

output "ireland_3_private_ip" {
  value = try(module.replicaset_ireland_3.private_ips[0], null)
}

output "multiaz_public_ips" {
  value = {
    multiaz_1 = try(module.multiaz_1.public_ips[0], null)
    multiaz_2 = try(module.multiaz_2.public_ips[0], null)
    multiaz_3 = try(module.multiaz_3.public_ips[0], null)
  }
}

output "multiaz_private_ips" {
  value = {
    multiaz_1 = try(module.multiaz_1.private_ips[0], null)
    multiaz_2 = try(module.multiaz_2.private_ips[0], null)
    multiaz_3 = try(module.multiaz_3.private_ips[0], null)
  }
}

output "configsvr_public_ips" {
  value = {
    london  = try(module.configsvr_london.public_ips[0], null)
    ireland = try(module.configsvr_ireland.public_ips[0], null)
    paris   = try(module.configsvr_paris.public_ips[0], null)
  }
}

output "configsvr_private_ips" {
  value = {
    london  = try(module.configsvr_london.private_ips[0], null)
    ireland = try(module.configsvr_ireland.private_ips[0], null)
    paris   = try(module.configsvr_paris.private_ips[0], null)
  }
}

output "shard1_public_ips" {
  value = {
    london  = try(module.shard1_london.public_ips[0], null)
    ireland = try(module.shard1_ireland.public_ips[0], null)
    paris   = try(module.shard1_paris.public_ips[0], null)
  }
}

output "shard1_private_ips" {
  value = {
    london  = try(module.shard1_london.private_ips[0], null)
    ireland = try(module.shard1_ireland.private_ips[0], null)
    paris   = try(module.shard1_paris.private_ips[0], null)
  }
}

output "mongos_public_ips" {
  value = {
    london  = try(module.mongos_london.public_ips[0], null)
    ireland = try(module.mongos_ireland.public_ips[0], null)
    paris   = try(module.mongos_paris.public_ips[0], null)
  }
}

output "mongos_private_ips" {
  value = {
    london  = try(module.mongos_london.private_ips[0], null)
    ireland = try(module.mongos_ireland.private_ips[0], null)
    paris   = try(module.mongos_paris.private_ips[0], null)
  }
}
