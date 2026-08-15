terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Single set of credentials, three regional aliases. Cross-region TGW
# peering needs both sides of a peering attachment created in the same
# apply, which is why this lab is one root module with aliased
# providers rather than three independent Terraform states per region.
provider "aws" {
  alias  = "london"
  region = "eu-west-2"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "ireland"
  region = "eu-west-1"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "paris"
  region = "eu-west-3"

  default_tags {
    tags = local.common_tags
  }
}
