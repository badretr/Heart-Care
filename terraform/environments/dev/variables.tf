variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "heartcare"
}

variable "owner" {
  type        = string
  description = "Resource owner"
  default     = "DevOps Team"
}

# Network variables
variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR"
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs"
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "Private app subnet CIDRs"
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "Private DB subnet CIDRs"
  default     = ["10.20.21.0/24", "10.20.22.0/24"]
}

# Compute variables
variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances"
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances"
  default     = 3
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of instances"
  default     = 2
}

# Database variables
variable "db_instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "RDS allocated storage"
  default     = 20
}

variable "db_username" {
  type        = string
  description = "Database username"
  default     = "heartcare"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database password"

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters."
  }
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "heartcare"
}

variable "backup_retention_days" {
  type        = number
  description = "Backup retention days"
  default     = 7
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ"
  default     = false
}

# Storage variables
variable "enable_versioning" {
  type        = bool
  description = "Enable S3 versioning"
  default     = true
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption"
  default     = true
}

# IAM variables
variable "create_iam_role" {
  type        = bool
  description = "Create the application IAM role. Keep false on AWS Academy Learner Lab (iam:CreateRole is denied); set true on a standard AWS account."
  default     = false
}

variable "existing_role_name" {
  type        = string
  description = "Pre-provisioned IAM role bound to the instance profile when create_iam_role is false"
  default     = "LabRole"
}

variable "created_at" {
  type        = string
  description = "Creation date stamped on the CreatedAt tag. Kept static on purpose: timestamp() would change on every run, forcing a pointless update of every resource on each apply."
  default     = "2026-11-13"
}

variable "enable_iam_tags" {
  type        = bool
  description = "Taguer les ressources IAM. Garder false sur AWS Academy Learner Lab, qui refuse iam:TagPolicy et iam:TagInstanceProfile ; passer a true sur un compte AWS standard."
  default     = false
}

variable "certificate_arn" {
  type        = string
  description = "ARN du certificat ACM servant le listener HTTPS de l'ALB. Vide : l'application est servie en HTTP uniquement."
  default     = ""
}
