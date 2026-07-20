terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same state bucket/lock table as infra/, under its own key so the two
  # stacks never share state. CI supplies bucket/key/region/dynamodb_table
  # via `terraform init -backend-config=...` (see infra/providers.tf).
  backend "s3" {}
}

provider "aws" {
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
