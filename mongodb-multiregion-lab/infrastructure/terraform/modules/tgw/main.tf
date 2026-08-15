terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_ec2_transit_gateway" "this" {
  description = var.name

  amazon_side_asn = var.amazon_side_asn

  # Auto-accept is off deliberately — peering attachments between
  # regions are accepted explicitly via the accepter resource in the
  # tgw-peering module, not silently. Same-region VPC attachment below
  # still auto-associates/propagates since there's no trust boundary
  # to reason about within one region's own TGW.
  auto_accept_shared_attachments = "disable"

  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "disable"

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id              = var.vpc_id
  subnet_ids          = var.subnet_ids

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation  = true

  tags = merge(var.tags, { Name = "${var.name}-vpc-attachment" })
}

# The default TGW route table is created implicitly by AWS — this data
# source looks it up so the root module can add static routes for
# peered regions onto it (peering routes are never auto-propagated,
# they always need an explicit aws_ec2_transit_gateway_route).
data "aws_ec2_transit_gateway_route_table" "default" {
  filter {
    name   = "transit-gateway-id"
    values = [aws_ec2_transit_gateway.this.id]
  }

  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
