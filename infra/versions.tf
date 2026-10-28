terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Values (bucket, key, region) are injected at init time by the pipeline:
  #   terraform init -backend-config="bucket=..." -backend-config="key=..." ...
  # use_lockfile enables native S3 state locking (no DynamoDB table needed).
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "github-actions"
    }
  }
}
