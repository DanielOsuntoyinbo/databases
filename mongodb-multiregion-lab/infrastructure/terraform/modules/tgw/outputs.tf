output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "tgw_route_table_id" {
  value = data.aws_ec2_transit_gateway_route_table.default.id
}

output "vpc_attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.this.id
}
