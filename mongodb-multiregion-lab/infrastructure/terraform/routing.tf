# Peering attachments never auto-propagate routes, unlike same-region
# VPC attachments (which do, via default_route_table_propagation on the
# tgw module). Every cross-region route below is therefore explicit.
# Two layers per direction:
#   1. TGW route table -> peer CIDR, via the peering attachment
#   2. VPC route table -> peer CIDR, via the local TGW
# Miss either layer and traffic silently black-holes in one direction
# only, which is the classic hard-to-spot TGW peering mistake — worth
# checking both explicitly during Phase 1 validation, not just "can I
# ping."

# The accepter resource reports complete as soon as AWS accepts the
# handshake, but the attachment itself can take a short while longer to
# actually reach "available" state — especially for cross-region
# peering. Creating a TGW route against an attachment that's still
# transitioning fails with IncorrectState. This wait absorbs that gap
# rather than making you re-run apply after a failure every time.
resource "time_sleep" "wait_for_peering" {
  create_duration = "90s"

  depends_on = [
    module.peering_london_ireland,
    module.peering_ireland_paris,
    module.peering_london_paris,
  ]
}

# --- London TGW route table ---

resource "aws_ec2_transit_gateway_route" "london_to_ireland" {
  provider = aws.london

  transit_gateway_route_table_id = module.tgw_london.tgw_route_table_id
  destination_cidr_block         = var.regions["ireland"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_london_ireland.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

resource "aws_ec2_transit_gateway_route" "london_to_paris" {
  provider = aws.london

  transit_gateway_route_table_id = module.tgw_london.tgw_route_table_id
  destination_cidr_block         = var.regions["paris"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_london_paris.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

# --- Ireland TGW route table ---

resource "aws_ec2_transit_gateway_route" "ireland_to_london" {
  provider = aws.ireland

  transit_gateway_route_table_id = module.tgw_ireland.tgw_route_table_id
  destination_cidr_block         = var.regions["london"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_london_ireland.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

resource "aws_ec2_transit_gateway_route" "ireland_to_paris" {
  provider = aws.ireland

  transit_gateway_route_table_id = module.tgw_ireland.tgw_route_table_id
  destination_cidr_block         = var.regions["paris"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_ireland_paris.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

# --- Paris TGW route table ---

resource "aws_ec2_transit_gateway_route" "paris_to_london" {
  provider = aws.paris

  transit_gateway_route_table_id = module.tgw_paris.tgw_route_table_id
  destination_cidr_block         = var.regions["london"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_london_paris.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

resource "aws_ec2_transit_gateway_route" "paris_to_ireland" {
  provider = aws.paris

  transit_gateway_route_table_id = module.tgw_paris.tgw_route_table_id
  destination_cidr_block         = var.regions["ireland"].vpc_cidr
  transit_gateway_attachment_id  = module.peering_ireland_paris.peering_attachment_id

  depends_on = [time_sleep.wait_for_peering]
}

# --- VPC route tables: send peer-region CIDRs to the local TGW ---

resource "aws_route" "london_to_ireland_vpc" {
  provider = aws.london

  route_table_id         = module.network_london.route_table_id
  destination_cidr_block = var.regions["ireland"].vpc_cidr
  transit_gateway_id     = module.tgw_london.tgw_id
}

resource "aws_route" "london_to_paris_vpc" {
  provider = aws.london

  route_table_id         = module.network_london.route_table_id
  destination_cidr_block = var.regions["paris"].vpc_cidr
  transit_gateway_id     = module.tgw_london.tgw_id
}

resource "aws_route" "ireland_to_london_vpc" {
  provider = aws.ireland

  route_table_id         = module.network_ireland.route_table_id
  destination_cidr_block = var.regions["london"].vpc_cidr
  transit_gateway_id     = module.tgw_ireland.tgw_id
}

resource "aws_route" "ireland_to_paris_vpc" {
  provider = aws.ireland

  route_table_id         = module.network_ireland.route_table_id
  destination_cidr_block = var.regions["paris"].vpc_cidr
  transit_gateway_id     = module.tgw_ireland.tgw_id
}

resource "aws_route" "paris_to_london_vpc" {
  provider = aws.paris

  route_table_id         = module.network_paris.route_table_id
  destination_cidr_block = var.regions["london"].vpc_cidr
  transit_gateway_id     = module.tgw_paris.tgw_id
}

resource "aws_route" "paris_to_ireland_vpc" {
  provider = aws.paris

  route_table_id         = module.network_paris.route_table_id
  destination_cidr_block = var.regions["ireland"].vpc_cidr
  transit_gateway_id     = module.tgw_paris.tgw_id
}
