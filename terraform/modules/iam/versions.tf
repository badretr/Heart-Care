terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # Les ressources IAM utilisent un provider sans default_tags : AWS Academy
      # Learner Lab refuse iam:TagPolicy et iam:TagInstanceProfile, et les tags
      # injectes globalement feraient echouer leur creation. Le tagging IAM est
      # pilote explicitement par var.enable_iam_tags.
      configuration_aliases = [aws.untagged]
    }
  }
}
