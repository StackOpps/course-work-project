terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same state bucket/lock table as infra/ and backup/, under its own key so
  # this stack never shares state with either. CI supplies bucket/key/region
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
