terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

# No NAT Gateway by design: nodes sit in public subnets with a
# restrictive security group (egress-only for PSMDB repo installs,
# no inbound except via SSM). This avoids the NAT Gateway hourly +
# per-GB cost that would otherwise be the single biggest line item
# across 3 regions. Security groups are defined in Phase 2 alongside
# the EC2 fleet, once we know exactly what needs to talk to what.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.azs[count.index]}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  # Deliberately no inline `route {}` block here. Every route for this
  # table — including the default IGW route below — is a standalone
  # aws_route resource instead. Mixing an inline route block with
  # separate aws_route resources on the same table causes Terraform to
  # treat the inline block as authoritative and delete any route it
  # didn't declare itself, which silently breaks the cross-region
  # routes added in routing.tf on the next apply.
  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "default_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
