variable "project_name" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "owner" {
  type        = string
  description = "Resource owner"
  default     = "DevOps"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}

variable "app_bucket_arn" {
  type        = string
  description = "ARN of the application S3 bucket the instances may read and write"
}

variable "logs_bucket_arn" {
  type        = string
  description = "ARN of the logs S3 bucket the instances may write to"
}

variable "create_iam_role" {
  type        = bool
  description = "Create the application IAM role. Must stay false on AWS Academy Learner Lab, which denies iam:CreateRole; set to true on a standard AWS account."
  default     = false
}

variable "enable_iam_tags" {
  type        = bool
  description = "Tag the IAM resources. Must stay false on AWS Academy Learner Lab, which denies iam:TagPolicy and iam:TagInstanceProfile; set to true on a standard AWS account."
  default     = false
}

variable "existing_role_name" {
  type        = string
  description = "Pre-provisioned IAM role to bind to the instance profile when create_iam_role is false"
  default     = "LabRole"
}
