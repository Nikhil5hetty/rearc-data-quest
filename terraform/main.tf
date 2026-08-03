terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend — configured per environment via GitHub Actions or Makefile.
  # Uncomment and fill in once you have a state bucket:
  # backend "s3" {
  #   bucket         = "rearc-tf-state-<account-id>"
  #   key            = "rearc-data-quest/<env>/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "rearc-tf-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
