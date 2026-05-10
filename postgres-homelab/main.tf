terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
  }

  # Once you're comfortable, migrate state to Terraform Cloud or an S3-compatible
  # backend (e.g. Hetzner Object Storage) so state is never just on your laptop.
  # For now, local state is fine to get started.
}

provider "hcloud" {
  # Token is read from HCLOUD_TOKEN environment variable — never hardcode it here.
  # export HCLOUD_TOKEN="your-token" in your ~/.bashrc
}
