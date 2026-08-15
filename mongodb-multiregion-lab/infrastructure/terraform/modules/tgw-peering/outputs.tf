output "peering_attachment_id" {
  description = "Shared attachment ID — identical on both the requester and accepter side, usable directly in TGW static routes in either region"
  value       = aws_ec2_transit_gateway_peering_attachment.this.id
}
