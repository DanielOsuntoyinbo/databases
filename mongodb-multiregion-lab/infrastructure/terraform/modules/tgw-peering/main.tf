terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.requester, aws.accepter]
    }
  }
}

# Requester side lives in the "from" region.
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  provider = aws.requester

  transit_gateway_id      = var.requester_tgw_id
  peer_transit_gateway_id = var.accepter_tgw_id
  peer_region             = var.accepter_region

  tags = merge(var.tags, { Name = var.name })
}

# Accepter side must run against the peer region's provider or the
# attachment sits in pendingAcceptance forever — this is the step
# that's easy to forget when peering TGWs by hand in the console.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  provider = aws.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this.id

  tags = merge(var.tags, { Name = var.name })
}
