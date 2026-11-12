variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "heartcare"
}

variable "enable_lock_table" {
  type        = bool
  description = "Enable DynamoDB lock table"
  default     = true
}
