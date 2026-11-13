# Variables de l'environnement prod.
# Environnement final. Haute disponibilite activee.
#
# Ce fichier EST versionne, et c'est voulu : il doit etre la seule source de
# verite des valeurs d'entree, partagee par le poste de developpement et le
# pipeline. Lorsqu'il ne l'etait pas, la CI retombait sur les defauts des
# variables, divergeait du local sur un simple tag, et recalculait une
# modification sur toutes les ressources.
#
# IL NE CONTIENT AUCUN SECRET. Le mot de passe de la base vient de
#     export TF_VAR_db_password='<mot-de-passe>'
# en local, et du secret GitHub TF_VAR_DB_PASSWORD dans le pipeline.

# Region et identification
aws_region   = "us-east-1"
environment  = "prod"
project_name = "heartcare"
owner        = "DevOps Team"

# Reseau
vpc_cidr                 = "10.20.0.0/16"
availability_zones       = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs      = ["10.20.1.0/24", "10.20.2.0/24"]
private_app_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
private_db_subnet_cidrs  = ["10.20.21.0/24", "10.20.22.0/24"]

# Calcul
instance_type    = "t3.medium"
min_size         = 3
max_size         = 8
desired_capacity = 4

# Base de donnees
db_instance_class     = "db.t3.medium"
db_allocated_storage  = 50
db_username           = "heartcare"
db_name               = "heartcare"
backup_retention_days = 30
multi_az              = true

# Stockage
enable_versioning = true
enable_encryption = true

# IAM
# false sur AWS Academy Learner Lab : iam:CreateRole, iam:AttachRolePolicy,
# iam:TagPolicy et iam:TagInstanceProfile y sont refuses par une SCP.
# Passer les deux a true sur un compte AWS standard.
create_iam_role    = false
enable_iam_tags    = false
existing_role_name = "LabRole"
