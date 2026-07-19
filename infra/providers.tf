terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # State bucket, lock table, and encryption must already exist — created
  # once by hand (or a separate bootstrap stack), since Terraform can't
  # create the backend it depends on to run. Left as an empty (partial)
  # backend block on purpose: CI supplies bucket/region/dynamodb_table plus
  # a `key` via `terraform init -backend-config=...`, which lets this same
  # configuration be re-applied under a second state key targeting
  # var.dr_region during a DR failover, without duplicating every resource
  # file for a second root module.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "crafthaven"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
