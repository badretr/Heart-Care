locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CreatedAt   = timestamp()
  }
}

# Network Module
module "network" {
  source = "../../modules/network"

  vpc_cidr                     = var.vpc_cidr
  availability_zones           = var.availability_zones
  public_subnet_cidrs          = var.public_subnet_cidrs
  private_app_subnet_cidrs     = var.private_app_subnet_cidrs
  private_db_subnet_cidrs      = var.private_db_subnet_cidrs
  environment                  = var.environment
  project_name                 = var.project_name
  owner                        = var.owner
  common_tags                  = local.common_tags
}

# Security Module
module "security" {
  source = "../../modules/security"

  vpc_id       = module.network.vpc_id
  environment  = var.environment
  project_name = var.project_name
  owner        = var.owner
  common_tags  = local.common_tags
}

# Database Module
module "database" {
  source = "../../modules/database"

  private_db_subnet_ids    = module.network.private_db_subnet_ids
  rds_security_group_id    = module.security.rds_security_group_id
  environment              = var.environment
  project_name             = var.project_name
  db_instance_class        = var.db_instance_class
  allocated_storage        = var.db_allocated_storage
  db_username              = var.db_username
  db_password              = var.db_password
  db_name                  = var.db_name
  backup_retention_days    = var.backup_retention_days
  multi_az                 = var.multi_az
  owner                    = var.owner
  common_tags              = local.common_tags
}

# Load Balancer Module
module "load_balancer" {
  source = "../../modules/load-balancer"

  vpc_id                  = module.network.vpc_id
  public_subnet_ids       = module.network.public_subnet_ids
  alb_security_group_id   = module.security.alb_security_group_id
  environment             = var.environment
  project_name            = var.project_name
  owner                   = var.owner
  common_tags             = local.common_tags
}

# Compute Module (Auto Scaling)
module "compute" {
  source = "../../modules/compute"

  private_app_subnet_ids       = module.network.private_app_subnet_ids
  app_security_group_id        = module.security.app_security_group_id
  target_group_arn             = module.load_balancer.target_group_arn
  iam_instance_profile_name    = module.security.app_instance_profile_name
  environment                  = var.environment
  project_name                 = var.project_name
  instance_type                = var.instance_type
  min_size                     = var.min_size
  max_size                     = var.max_size
  desired_capacity             = var.desired_capacity
  db_host                      = split(":", module.database.db_instance_endpoint)[0]
  db_name                      = var.db_name
  db_user                      = var.db_username
  owner                        = var.owner
  common_tags                  = local.common_tags

  depends_on = [module.database]
}

# Storage Module
module "storage" {
  source = "../../modules/storage"

  environment              = var.environment
  project_name             = var.project_name
  enable_versioning        = var.enable_versioning
  enable_encryption        = var.enable_encryption
  owner                    = var.owner
  common_tags              = local.common_tags
}
