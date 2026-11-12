# Terraform - Heart Care Application Infrastructure

## 📚 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Architecture](#architecture)
3. [Prérequis](#prérequis)
4. [Démarrage rapide](#démarrage-rapide)
5. [Structure du projet](#structure-du-projet)
6. [Modules](#modules)
7. [Environnements](#environnements)
8. [Déploiement](#déploiement)
9. [Tests](#tests)
10. [Destruction](#destruction)
11. [Dépannage](#dépannage)

## 🎯 Vue d'ensemble

Ce projet Terraform définit une infrastructure Cloud **hautement disponible** sur AWS pour l'application Heart Care (Django). L'infrastructure est entièrement modulaire et reproductible dans plusieurs environnements (dev, test, prod).

### Points clés
- ✅ **Infrastructure as Code** : Entièrement versionnable dans Git
- ✅ **Multi-environnements** : dev, test, prod avec configurations spécifiques
- ✅ **Haute disponibilité** : Load Balancer + Auto Scaling + Multi-AZ (prod)
- ✅ **Sécurité** : Subnets privés, Security Groups minimaux, chiffrement
- ✅ **CI/CD intégré** : Pipeline GitHub Actions automatisé
- ✅ **État distant sécurisé** : Backend S3 + DynamoDB lock

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud (eu-west-1)                │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ VPC: 10.20.0.0/16                                     │  │
│  │ ┌─────────────────────────────────────────────────┐  │  │
│  │ │ Internet Gateway                                │  │  │
│  │ └─────────────────────────────────────────────────┘  │  │
│  │                        ↓                               │  │
│  │  ┌──────────────────────┴──────────────────────────┐ │  │
│  │  │  Public Subnets (ALB)                           │ │  │
│  │  │  10.20.1.0/24 (eu-west-1a)                     │ │  │
│  │  │  10.20.2.0/24 (eu-west-1b)                     │ │  │
│  │  │                                                 │ │  │
│  │  │  ┌──────────────────────────────────────────┐  │ │  │
│  │  │  │ Application Load Balancer                │  │ │  │
│  │  │  │ Port: 80 (HTTP), 443 (HTTPS)            │  │ │  │
│  │  │  └─────────────────────┬────────────────────┘  │ │  │
│  │  └──────────────────────────────────────────────┘ │  │
│  │                        ↓                            │  │
│  │  ┌──────────────────────┴──────────────────────┐  │  │
│  │  │ Private Subnets - App (Instances)           │  │  │
│  │  │ 10.20.11.0/24 (eu-west-1a)                 │  │  │
│  │  │ 10.20.12.0/24 (eu-west-1b)                 │  │  │
│  │  │                                              │  │  │
│  │  │ ┌─────────────┐  ┌─────────────┐           │  │  │
│  │  │ │ Instance 1  │  │ Instance 2  │           │  │  │
│  │  │ │ Django App  │  │ Django App  │           │  │  │
│  │  │ │ Port: 8000  │  │ Port: 8000  │           │  │  │
│  │  │ └─────────────┘  └─────────────┘           │  │  │
│  │  └─────────────────────┬──────────────────────┘  │  │
│  │                        ↓                          │  │
│  │  ┌──────────────────────┴──────────────────────┐  │  │
│  │  │ Private Subnets - Database (RDS)            │  │  │
│  │  │ 10.20.21.0/24 (eu-west-1a)                 │  │  │
│  │  │ 10.20.22.0/24 (eu-west-1b)                 │  │  │
│  │  │                                              │  │  │
│  │  │ ┌───────────────────────────────────────┐  │  │  │
│  │  │ │ RDS PostgreSQL (db.t3.micro)          │  │  │  │
│  │  │ │ Database: heartcare                   │  │  │  │
│  │  │ │ Port: 5432 (Private Access Only)      │  │  │  │
│  │  │ └───────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────┘  │  │
│                                                       │  │
│  ┌─────────────────────────────────────────────────┐ │  │
│  │ S3 Buckets (Assets, Logs, Backups)              │ │  │
│  └─────────────────────────────────────────────────┘ │  │
└─────────────────────────────────────────────────────────┘

Backend State:
┌────────────────────────────────────────┐
│ S3 Bucket (Terraform State)             │
│ - Versioning: Enabled                  │
│ - Encryption: AES256                   │
│ - Public Access: Blocked                │
│                                         │
│ DynamoDB Table (State Lock)             │
│ - Prevents concurrent modifications    │
└────────────────────────────────────────┘
```

## 📋 Prérequis

### Logiciels
- **Terraform** >= 1.6.0
- **AWS CLI** v2
- **Git**
- **Bash** (pour les scripts)

### Cloud
- **Compte AWS** avec permissions pour :
  - EC2, ECS, RDS, ALB
  - VPC, Security Groups
  - IAM Roles & Policies
  - S3, CloudWatch
  - KMS (pour chiffrement)

### Authentification AWS

Option 1 : Variables d'environnement
```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_REGION="eu-west-1"
```

Option 2 : AWS CLI
```bash
aws configure
```

## 🚀 Démarrage rapide

### 1️⃣ Bootstrap du Backend

```bash
# Aller dans le répertoire bootstrap
cd terraform/bootstrap

# Créer les ressources pour l'état Terraform
bash ../scripts/bootstrap.sh eu-west-1

# Cette commande va :
# - Créer un bucket S3 pour l'état Terraform
# - Créer une table DynamoDB pour le verrouillage
# - Afficher les configurations backend
```

### 2️⃣ Initialiser l'environnement DEV

```bash
cd terraform/environments/dev

# Créer terraform.tfvars
cp terraform.tfvars.example terraform.tfvars

# Éditer terraform.tfvars et changer le mot de passe DB
nano terraform.tfvars

# Initialiser Terraform
terraform init \
  -backend-config=bucket=heartcare-terraform-state-ACCOUNT_ID \
  -backend-config=key=dev/terraform.tfstate \
  -backend-config=region=eu-west-1 \
  -backend-config=encrypt=true \
  -backend-config=dynamodb_table=heartcare-terraform-lock
```

### 3️⃣ Planifier et Appliquer

```bash
# Vérifier le format
terraform fmt -check -recursive

# Valider la configuration
terraform validate

# Planifier les changements
terraform plan -out=tfplan

# Appliquer les changements
terraform apply tfplan
```

### 4️⃣ Accéder à l'application

```bash
# Récupérer l'URL du Load Balancer
terraform output alb_dns_name

# Ou
terraform output application_url

# Ouvrir dans le navigateur
open http://$(terraform output -raw alb_dns_name)
```

## 📁 Structure du projet

```
terraform/
├── bootstrap/                    # Bootstrap du backend
│   ├── main.tf                  # S3 + DynamoDB
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── modules/                     # Modules réutilisables
│   ├── network/                # VPC, Subnets, Routage
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   ├── security/               # Security Groups, IAM
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   ├── load-balancer/          # ALB, Target Groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   ├── compute/                # Launch Template, ASG
│   │   ├── main.tf
│   │   ├── user_data.sh        # Script d'installation
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   ├── database/               # RDS PostgreSQL
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   └── storage/                # S3 Buckets
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
│
├── environments/
│   ├── dev/                    # Environnement de développement
│   │   ├── main.tf             # Orchestration des modules
│   │   ├── variables.tf        # Variables spécifiques
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── terraform.tfvars.example
│   │
│   ├── test/                   # Environnement de test
│   │   └── [même structure que dev]
│   │
│   └── prod/                   # Environnement de production
│       └── [même structure que dev]
│
├── scripts/
│   ├── bootstrap.sh            # Script de bootstrap
│   └── deploy.sh               # Script de déploiement
│
└── README.md                   # Cette documentation
```

## 🔧 Modules

### Network Module
**Ressources** : VPC, Subnets (publics/privés), Internet Gateway, NAT Gateways, Route Tables

**Inputs** :
- `vpc_cidr` : CIDR du VPC (défaut: 10.20.0.0/16)
- `availability_zones` : Zones de disponibilité
- `public_subnet_cidrs` : CIDRs des subnets publics
- `private_app_subnet_cidrs` : CIDRs des subnets privés App
- `private_db_subnet_cidrs` : CIDRs des subnets privés DB

**Outputs** :
- `vpc_id`, `vpc_cidr`
- `public_subnet_ids`, `private_app_subnet_ids`, `private_db_subnet_ids`
- `internet_gateway_id`, `nat_gateway_ids`

### Security Module
**Ressources** : Security Groups (ALB, App, RDS, Bastion), IAM Roles, SSM Parameters

**Inputs** :
- `vpc_id` : VPC ID
- `environment`, `project_name`, `owner`

**Outputs** :
- `alb_security_group_id`, `app_security_group_id`, `rds_security_group_id`
- `app_instance_role_arn`, `app_instance_profile_name`

### Load Balancer Module
**Ressources** : ALB, Target Groups, Listeners

**Inputs** :
- `vpc_id`, `public_subnet_ids`
- `alb_security_group_id`
- `health_check_path` (défaut: "/")

**Outputs** :
- `alb_arn`, `alb_dns_name`, `alb_url`
- `target_group_arn`

### Compute Module
**Ressources** : Launch Template, Auto Scaling Group, CloudWatch Alarms

**Inputs** :
- `private_app_subnet_ids`, `app_security_group_id`
- `target_group_arn`, `iam_instance_profile_name`
- `instance_type` (défaut: t3.micro)
- `min_size`, `max_size`, `desired_capacity`

**Outputs** :
- `launch_template_id`
- `autoscaling_group_name`, `autoscaling_group_arn`

### Database Module
**Ressources** : RDS Instance, DB Subnet Group, Parameter Group, SSM Parameters

**Inputs** :
- `private_db_subnet_ids`, `rds_security_group_id`
- `db_instance_class` (défaut: db.t3.micro)
- `allocated_storage` (défaut: 20 GB)
- `db_username`, `db_password`, `db_name`
- `backup_retention_days` (défaut: 7)
- `multi_az` (défaut: false)

**Outputs** :
- `db_instance_endpoint`, `db_instance_address`, `db_instance_port`
- `db_name`, `db_username`
- `db_connection_string`

### Storage Module
**Ressources** : S3 Buckets (App + Logs), Policies, Lifecycle, Versioning

**Inputs** :
- `environment`, `project_name`
- `enable_versioning` (défaut: true)
- `enable_encryption` (défaut: true)

**Outputs** :
- `s3_bucket_id`, `s3_bucket_arn`
- `s3_logs_bucket_id`

## 🌍 Environnements

### DEV (Développement)
- **Instance** : t3.micro (min: 2, max: 3)
- **Database** : db.t3.micro, 20 GB, backup: 7 jours
- **Multi-AZ** : Non
- **Coût** : ~$8/mois
- **Déploiement** : Automatique depuis la branche `develop`

### TEST (Test)
- **Instance** : t3.small (min: 2, max: 4)
- **Database** : db.t3.small, 30 GB, backup: 14 jours
- **Multi-AZ** : Non
- **Coût** : ~$20/mois
- **Déploiement** : Après approbation depuis `main`

### PROD (Production)
- **Instance** : t3.medium (min: 3, max: 8)
- **Database** : db.t3.medium, 50 GB, backup: 30 jours, **Multi-AZ: Oui**
- **Multi-AZ** : Oui
- **Coût** : ~$60/mois
- **Déploiement** : Approbation manuelle requise

## 🚀 Déploiement

### Méthode 1 : Script de déploiement

```bash
# Plan pour DEV
cd terraform/environments/dev
bash ../../scripts/deploy.sh dev plan

# Apply pour DEV
bash ../../scripts/deploy.sh dev apply

# Destroy (ATTENTION!)
bash ../../scripts/deploy.sh dev destroy
```

### Méthode 2 : Commandes manuelles

```bash
cd terraform/environments/dev

# Vérifier le format
terraform fmt -check -recursive

# Valider
terraform validate

# Planifier
terraform plan -out=tfplan

# Voir le plan
terraform show tfplan

# Appliquer
terraform apply tfplan

# Voir les outputs
terraform output
```

### Méthode 3 : CI/CD GitHub Actions

1. Push vers `develop` → Plan auto pour DEV
2. Merge vers `main` → Plan auto pour TEST + attente approbation
3. PR vers `main` → Plan affiché en commentaire
4. Merge vers `main` → Apply auto pour TEST

## 🧪 Tests obligatoires

```bash
cd terraform/environments/dev

# ✅ Format
terraform fmt -check -recursive

# ✅ Validation
terraform validate

# ✅ Plan
terraform plan

# ✅ Accès Web
curl http://$(terraform output -raw alb_dns_name)

# ✅ Répartition de charge
for i in {1..5}; do curl -s http://$(terraform output -raw alb_dns_name) | grep Instance; done

# ✅ Panne d'instance
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw autoscaling_group_name)" \
  --query 'Reservations[0].Instances[0].InstanceId'
# Arrêter une instance
aws ec2 stop-instances --instance-ids <id>
# Vérifier que le service continue

# ✅ Sécurité DB
psql -h $(terraform output -raw db_endpoint | cut -d: -f1) -U heartcare -d heartcare
# Doit échouer depuis Internet (seuls les instances privées peuvent accéder)

# ✅ Auto Scaling
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $(terraform output -raw autoscaling_group_name) \
  --desired-capacity 4
# Attendre que les instances se créent
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $(terraform output -raw autoscaling_group_name) \
  --desired-capacity 2
# Attendre que les instances se détruisent
```

## 🗑️ Destruction

⚠️ **DANGER** : Cette action supprime TOUTES les ressources AWS !

```bash
cd terraform/environments/dev

# Voir ce qui sera supprimé
terraform plan -destroy

# Supprimer
terraform destroy

# Ou via le script
bash ../../scripts/deploy.sh dev destroy
```

### Ordre de destruction (important)
1. Détruire DEV
2. Détruire TEST
3. Détruire PROD (si créé)
4. Détruire BOOTSTRAP (dernière étape)

```bash
cd terraform/bootstrap
terraform destroy
```

## 🐛 Dépannage

### Erreur : "Backend configuration missing"

```bash
# Solution : Initialiser avec backend
terraform init \
  -backend-config=bucket=heartcare-terraform-state-XXX \
  -backend-config=key=dev/terraform.tfstate \
  -backend-config=region=eu-west-1 \
  -backend-config=encrypt=true
```

### Erreur : "Error acquiring the state lock"

```bash
# La table DynamoDB existe mais est verrouillée
# Options :
# 1. Attendre (le verrou dure généralement quelques secondes)
# 2. Nettoyer le verrou :
aws dynamodb delete-item \
  --table-name heartcare-terraform-lock \
  --key '{"LockID":{"S":"heartcare-dev"}}'
```

### Erreur : "No space left on device" (S3 state)

```bash
# Limiter la taille du state
terraform state list
terraform state rm 'module.xxx[0]'
```

### Les instances ne sont pas saines

```bash
# Vérifier les logs
aws ssm start-session --target <instance-id>
tail -f /var/log/user-data.log
tail -f /var/log/heartcare-err.log

# Vérifier le ALB Target Group
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

### RDS ne répond pas

```bash
# Vérifier que la base est disponible
aws rds describe-db-instances \
  --db-instance-identifier heartcare-dev-db

# Vérifier les credentials
export PGPASSWORD="your-password"
psql -h <db-host> -U heartcare -d heartcare -c "SELECT 1"
```

## 📊 Coûts estimés (1 mois)

| Ressource | Quantité | Prix unitaire | Sous-total |
|-----------|----------|--------------|-----------|
| **DEV Environment** |
| EC2 t3.micro | 2 | $4 | $8 |
| RDS db.t3.micro | 1 | $8 | $8 |
| ALB | 1 | $16 | $16 |
| Data Transfer | — | — | $2 |
| **DEV Total** | | | **$34** |
| **TEST Environment** |
| EC2 t3.small | 3 | $8 | $24 |
| RDS db.t3.small | 1 | $12 | $12 |
| ALB | 1 | $16 | $16 |
| Data Transfer | — | — | $3 |
| **TEST Total** | | | **$55** |

⚠️ **Avec $50 de crédit AWS :**
- Déployer DEV uniquement (~$34/mois)
- Ou DEV + 2 semaines de TEST
- **Détruire immédiatement après tests !**

## 🔐 Sécurité

✅ **Points de sécurité implémentés :**
- VPC privé avec subnets isolés
- Security Groups minimaux (least privilege)
- Pas d'accès public à RDS
- Chiffrement S3 + state Terraform
- IAM roles spécifiques par ressource
- Secrets stockés dans SSM Parameter Store
- Pas de secrets en clair dans Git
- Verrouillage d'état Terraform (DynamoDB)
- Versioning S3 pour audit
- CloudWatch logs pour monitoring

⚠️ **À faire avant production :**
- Ajouter HTTPS/TLS
- Configurer WAF sur ALB
- Activer VPC Flow Logs
- Configurer AWS Config
- Activer AWS CloudTrail
- Mettre en place des alertes SNS/Slack

## 📚 Ressources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Architecture Best Practices](https://aws.amazon.com/architecture/)
- [Security Best Practices for AWS](https://aws.amazon.com/architecture/security-identity-compliance/)

## 📖 Auteurs et maintenance

- **Créé par** : Cloud & DevOps Team
- **Dernière mise à jour** : 2026-11-12
- **Version Terraform** : >= 1.6.0
- **Version AWS Provider** : ~> 5.0

---

**Besoin d'aide ?** Vérifiez la section [Dépannage](#dépannage) ou créez une issue sur le dépôt.
