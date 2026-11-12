variable "private_db_subnet_ids" {
  type        = list(string)
  description = "List of private DB subnet IDs"
}

variable "rds_security_group_id" {
  type        = string
  description = "RDS Security Group ID"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "heartcare"

  validation {
    condition     = length(var.db_name) <= 63
    error_message = "Database name must be 63 characters or less."
  }
}

variable "db_username" {
  type        = string
  description = "Database master username"
  default     = "heartcare"

  validation {
    condition     = length(var.db_username) <= 16
    error_message = "Database username must be 16 characters or less."
  }
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database master password"

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters."
  }
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB"
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 1000
    error_message = "Allocated storage must be between 20 and 1000 GB."
  }
}

variable "storage_type" {
  type        = string
  description = "Storage type"
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1"], var.storage_type)
    error_message = "Storage type must be gp2, gp3, or io1."
  }
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL version"
  default     = "15.4"
}

variable "backup_retention_days" {
  type        = number
  description = "Backup retention period in days"
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 0 and 35 days."
  }
}

variable "backup_window" {
  type        = string
  description = "Backup window"
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Maintenance window"
  default     = "sun:04:00-sun:05:00"
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = false
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "enable_cloudwatch_logs" {
  type        = bool
  description = "Enable CloudWatch logs"
  default     = true
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
