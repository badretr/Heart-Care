terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    # bucket         = "heartcare-terraform-state-XXX"
    # key            = "test/terraform.tfstate"
    # region         = "eu-west-1"
    # encrypt        = true
  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}
