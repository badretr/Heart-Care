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

output "db_password_parameter_name" {
  value       = aws_ssm_parameter.db_password.name
  description = "SSM Parameter name for database password"
}
