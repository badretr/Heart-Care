terraform {
  # >= 1.10 : le verrouillage natif S3 du backend (use_lockfile)
  # n'existe pas avant cette version.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend distant : etat stocke sur S3, chiffre, versionne, avec
  # verrouillage natif S3 (use_lockfile). Chaque environnement a sa propre
  # cle, ce qui isole les etats dev / test / prod.
  backend "s3" {
    bucket       = "heartcare-terraform-state-342766168998"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
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
