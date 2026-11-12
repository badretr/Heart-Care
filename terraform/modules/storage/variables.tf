variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project_name" {
  type        = string
  description = "Project name"
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

variable "enable_versioning" {
  type        = bool
  description = "Enable versioning for S3 bucket"
  default     = true
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption for S3 bucket"
  default     = true
}

variable "lifecycle_expiration_days" {
  type        = number
  description = "Days before non-current versions expire"
  default     = 90

  validation {
    condition     = var.lifecycle_expiration_days >= 1
    error_message = "Expiration days must be at least 1."
  }
}

variable "block_public_access" {
  type        = bool
  description = "Block all public access to S3 bucket"
  default     = true
}
