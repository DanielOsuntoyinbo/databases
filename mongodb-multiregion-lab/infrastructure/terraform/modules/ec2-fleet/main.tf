terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_ami" "ubuntu_noble" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key pairs are regional in AWS — this imports the same public key
# (danny-pc's ~/.ssh/id_ed25519.pub, same key used for the Postgres
# homelab) into each region separately rather than generating new
# per-region keys.
resource "aws_key_pair" "admin" {
  key_name   = "${var.name}-admin"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "mongod" {
  name_prefix = "${var.name}-mongod-"
  description = "PSMDB replica set members - ${var.name}"
  vpc_id      = var.vpc_id

  # SSH from the admin workstation's public IP only — no bastion, no
  # SSM, same direct-access pattern as the Postgres homelab.
  ingress {
    description = "SSH from admin workstation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  # mongod replication traffic — scoped to this region's own VPC plus
  # the two peer VPC CIDRs, never 0.0.0.0/0. Local VPC CIDR is needed
  # here too since same-region members still replicate over this port.
  ingress {
    description = "mongod replication from local + peer region VPCs"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.mongod_ingress_cidrs
  }

  egress {
    description = "all outbound (PSMDB repo installs, cross-region replication)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-mongod-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "node" {
  count = var.node_count

  ami                    = coalesce(var.ami_id, data.aws_ami.ubuntu_noble.id)
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.admin.key_name
  vpc_security_group_ids = [aws_security_group.mongod.id]

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${var.node_role}-${count.index + 1}"
    Role = var.node_role
  })
}
