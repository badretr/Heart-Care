variable "private_app_subnet_ids" {
  type        = list(string)
  description = "List of private app subnet IDs"
}

variable "app_security_group_id" {
  type        = string
  description = "App Security Group ID"
}

variable "target_group_arn" {
  type        = string
  description = "Target Group ARN"
}

variable "iam_instance_profile_name" {
  type        = string
  description = "IAM Instance Profile name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances"
  default     = 2

  validation {
    condition     = var.min_size >= 1 && var.min_size <= 10
    error_message = "min_size must be between 1 and 10."
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances"
  default     = 4

  validation {
    condition     = var.max_size >= var.min_size && var.max_size <= 10
    error_message = "max_size must be >= min_size and <= 10."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of instances"
  default     = 2

  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 10
    error_message = "desired_capacity must be between 1 and 10."
  }
}

variable "health_check_type" {
  type        = string
  description = "Health check type"
  default     = "ELB"
}

variable "health_check_grace_period" {
  type        = number
  description = "Health check grace period in seconds"
  default     = 300
}

variable "db_host" {
  type        = string
  description = "Database host"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "heartcare"
}

variable "db_user" {
  type        = string
  description = "Database user"
  default     = "heartcare"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}

variable "owner" {
  type        = string
  description = "Resource owner"
  default     = "DevOps"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for instances"
  default     = ""  # Will use latest Ubuntu 22.04
}
