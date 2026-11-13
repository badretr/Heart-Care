# Network outputs
output "vpc_id" {
  value       = module.network.vpc_id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = module.network.vpc_cidr
  description = "VPC CIDR block"
}

output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "Public subnet IDs"
}

output "private_app_subnet_ids" {
  value       = module.network.private_app_subnet_ids
  description = "Private app subnet IDs"
}

output "private_db_subnet_ids" {
  value       = module.network.private_db_subnet_ids
  description = "Private DB subnet IDs"
}

# Load Balancer outputs
output "alb_dns_name" {
  value       = module.load_balancer.alb_dns_name
  description = "ALB DNS name"
}

output "alb_url" {
  value       = module.load_balancer.alb_url
  description = "ALB URL"
}

output "alb_arn" {
  value       = module.load_balancer.alb_arn
  description = "ALB ARN"
}

output "target_group_arn" {
  value       = module.load_balancer.target_group_arn
  description = "Target group ARN"
}

# Compute outputs
output "autoscaling_group_name" {
  value       = module.compute.autoscaling_group_name
  description = "Auto Scaling Group name"
}

output "autoscaling_group_arn" {
  value       = module.compute.autoscaling_group_arn
  description = "Auto Scaling Group ARN"
}

output "launch_template_id" {
  value       = module.compute.launch_template_id
  description = "Launch Template ID"
}

# Database outputs
output "db_endpoint" {
  value       = module.database.db_instance_endpoint
  description = "Database endpoint"
  sensitive   = true
}

output "db_name" {
  value       = module.database.db_name
  description = "Database name"
}

output "db_username" {
  value       = module.database.db_username
  description = "Database username"
  sensitive   = true
}

output "db_connection_string" {
  value       = module.database.db_connection_string
  description = "Database connection string"
  sensitive   = true
}

# Storage outputs
output "s3_bucket_id" {
  value       = module.storage.s3_bucket_id
  description = "S3 bucket ID"
}

output "s3_bucket_arn" {
  value       = module.storage.s3_bucket_arn
  description = "S3 bucket ARN"
}

# Application URL
output "application_url" {
  value       = "http://${module.load_balancer.alb_dns_name}"
  description = "Application URL"
}

# IAM outputs
output "iam_app_policy_arn" {
  value       = module.iam.app_policy_arn
  description = "ARN de la politique de moindre privilege des instances applicatives"
}

output "iam_app_instance_profile_name" {
  value       = module.iam.app_instance_profile_name
  description = "Instance profile gere par Terraform et attache aux instances"
}

output "iam_app_role_arn" {
  value       = module.iam.app_role_arn
  description = "Role IAM porte par l'instance profile applicatif"
}

output "iam_policy_attached_to_role" {
  value       = module.iam.policy_attached_to_role
  description = "Indique si la politique est rattachee au role (false sur Learner Lab: iam:AttachRolePolicy est refuse)"
}
