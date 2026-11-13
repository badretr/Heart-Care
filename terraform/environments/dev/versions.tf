terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "../../terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Provider sans default_tags, reserve aux ressources IAM : AWS Academy Learner
# Lab refuse iam:TagPolicy / iam:TagInstanceProfile, donc les tags injectes
# globalement feraient echouer la creation de ces ressources.
provider "aws" {
  alias  = "untagged"
  region = var.aws_region
}
