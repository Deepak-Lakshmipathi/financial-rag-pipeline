terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "financial-rag-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_region" "current" {}

locals {
  # Constructed without referencing the resource to break the sfn_starter Lambda ↔ SFN cycle
  sfn_pipeline_arn = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:financial-rag-pipeline"
}