variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs"
}

variable "alb_security_group_id" {
  type        = string
  description = "ALB Security Group ID"
}

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

variable "health_check_path" {
  type        = string
  description = "Health check path"
  default     = "/"
}

variable "health_check_interval" {
  type        = number
  description = "Health check interval in seconds"
  default     = 30
}

variable "health_check_timeout" {
  type        = number
  description = "Health check timeout in seconds"
  default     = 5
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Healthy threshold"
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Unhealthy threshold"
  default     = 2
}

variable "certificate_arn" {
  type        = string
  description = "ARN du certificat ACM servant le listener HTTPS. Vide : aucun listener HTTPS n'est cree et l'application est servie en HTTP."
  default     = ""
}

variable "ssl_policy" {
  type        = string
  description = "Politique TLS du listener HTTPS"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}
