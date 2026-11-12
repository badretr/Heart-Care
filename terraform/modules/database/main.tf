locals {
  common_tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  )
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-"
  subnet_ids  = var.private_db_subnet_ids

  tags = merge(
    local.common_tags,
    { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
  )
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-${var.environment}-db"
  engine                 = "postgres"
  engine_version         = var.engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.allocated_storage
  storage_type           = var.storage_type
  storage_encrypted      = var.enable_encryption
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]

  # Backup and maintenance
  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  multi_az                = var.multi_az

  # High availability
  auto_minor_version_upgrade = true
  deletion_protection        = false

  # Logging
  enabled_cloudwatch_logs_exports = var.enable_cloudwatch_logs ? [
    "postgresql"
  ] : []

  # Performance Insights
  performance_insights_enabled = false

  # Monitoring
  monitoring_interval                 = 0
  monitoring_role_arn                 = null
  iam_database_authentication_enabled = true

  # Parameters
  parameter_group_name = aws_db_parameter_group.main.name

  # Other
  publicly_accessible   = false
  skip_final_snapshot   = true
  copy_tags_to_snapshot = true

  depends_on = [
    aws_db_subnet_group.main,
  ]

  tags = merge(
    local.common_tags,
    { Name = "${var.project_name}-${var.environment}-db" }
  )
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-"
  family      = "postgres15"
  description = "Database parameter group for ${var.environment}"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(
    local.common_tags,
    { Name = "${var.project_name}-${var.environment}-param-group" }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Store password in SSM Parameter Store
resource "aws_ssm_parameter" "db_password_actual" {
  name        = "/${var.project_name}/${var.environment}/db/password"
  description = "Database password for ${var.environment}"
  type        = "SecureString"
  value       = var.db_password
  overwrite   = true

  tags = merge(
    local.common_tags,
    { Name = "${var.project_name}-${var.environment}-db-password" }
  )
}

# Store connection string in SSM Parameter Store
resource "aws_ssm_parameter" "db_connection_string" {
  name        = "/${var.project_name}/${var.environment}/db/connection-string"
  description = "Database connection string for ${var.environment}"
  type        = "String"
  value       = "postgresql://${var.db_username}@${aws_db_instance.main.endpoint}/${var.db_name}"

  tags = merge(
    local.common_tags,
    { Name = "${var.project_name}-${var.environment}-db-connection" }
  )
}
