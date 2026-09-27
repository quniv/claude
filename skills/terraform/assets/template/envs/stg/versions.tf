terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "__PREFIX__-tfstate-__ACCOUNT_ID__"
    key          = "envs/stg/terraform.tfstate"
    region       = "__REGION__"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = local.region

  allowed_account_ids = [local.account_id]

  default_tags {
    tags = {
      Environment = local.env
      ManagedBy   = "terraform"
      Repository  = "__GITHUB_ORG__/__GITHUB_REPO__"
      Stack       = "envs/stg"
    }
  }
}
