output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "subnet_ids" {
  value = aws_subnet.public[*].id
}

output "route_table_id" {
  value = aws_route_table.public.id
}
