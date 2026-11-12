output "db_instance_id" {
  value       = aws_db_instance.main.id
  description = "RDS instance ID"
}

output "db_instance_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS instance endpoint"
}

output "db_instance_address" {
  value       = aws_db_instance.main.address
  description = "RDS instance address"
}

output "db_instance_port" {
  value       = aws_db_instance.main.port
  description = "RDS instance port"
}

output "db_name" {
  value       = aws_db_instance.main.db_name
  description = "Database name"
}

output "db_username" {
  value       = aws_db_instance.main.username
  description = "Database master username"
  sensitive   = true
}

output "db_connection_string" {
  value       = aws_ssm_parameter.db_connection_string.value
  description = "Database connection string"
  sensitive   = true
}

output "db_password_parameter_name" {
  value       = aws_ssm_parameter.db_password_actual.name
  description = "SSM Parameter name for database password"
}

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.main.name
  description = "DB Subnet Group name"
}
