output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "ALB Security Group ID"
}

output "app_security_group_id" {
  value       = aws_security_group.app.id
  description = "App Security Group ID"
}

output "rds_security_group_id" {
  value       = aws_security_group.rds.id
  description = "RDS Security Group ID"
}

output "bastion_security_group_id" {
  value       = aws_security_group.bastion.id
  description = "Bastion Security Group ID"
}

output "app_instance_role_arn" {
  value       = data.aws_iam_instance_profile.app.role_arn
  description = "ARN of the app instance role"
}

output "app_instance_profile_name" {
  value       = data.aws_iam_instance_profile.app.name
  description = "Name of the app instance profile"
}

output "db_password_parameter_name" {
  value       = aws_ssm_parameter.db_password.name
  description = "SSM Parameter name for database password"
}
