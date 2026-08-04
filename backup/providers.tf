terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

# Two aliased providers instead of one implicit-region provider: this stack
# deploys the primary vault/plan (and its monitoring) into the primary
# region and the DR vault (and its monitoring) into the DR region in the
# same apply, so "which region is primary" can't drift based on which value
# happens to be passed as var.aws_region at apply time.
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "crafthaven"
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "backup"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "crafthaven"
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "backup"
    }
  }
}
