terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Restore testing plan/selection resources require a provider new
      # enough to support them.
      version = ">= 5.39, < 6.0"
    }
  }

  # Same state bucket/lock table as infra/, under its own key so the two
  # stacks never share state. CI supplies bucket/key/region/dynamodb_table
  # via `terraform init -backend-config=...` (see infra/providers.tf).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "crafthaven"
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "restore-testing"
    }
  }
}

data "aws_caller_identity" "current" {}
