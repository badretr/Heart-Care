# 🚀 QUICK START - Heart Care Infrastructure

**Durée totale** : ~40 minutes  
**Budget** : $50 crédit AWS  
**Complexité** : Intermédiaire

---

## 1️⃣ Prérequis (5 min)

```bash
# Vérifier les outils
terraform version    # >= 1.6.0
aws --version        # AWS CLI v2
git --version

# Vérifier AWS credentials
aws sts get-caller-identity
```

---

## 2️⃣ Bootstrap du Backend (5 min)

```bash
cd /home/terraform/Desktop/Heart-Care-main/terraform/bootstrap

# Créer S3 bucket + DynamoDB table
bash ../scripts/bootstrap.sh eu-west-1

# Copier le bucket name de la sortie
export BUCKET_NAME=heartcare-terraform-state-XXXXXXXXXX
```

---

## 3️⃣ Déployer DEV (20 min)

```bash
cd ../environments/dev

# 1. Créer terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# ⚠️ Éditer et changer db_password!

# 2. Initialiser Terraform
terraform init \
  -backend-config=bucket=$BUCKET_NAME \
  -backend-config=key=dev/terraform.tfstate \
  -backend-config=region=eu-west-1 \
  -backend-config=encrypt=true \
  -backend-config=dynamodb_table=heartcare-terraform-lock

# 3. Plan
terraform plan -out=tfplan

# 4. Apply
terraform apply tfplan
```

---

## 4️⃣ Tester (5 min)

```bash
# Récupérer l'URL
ALB_URL=$(terraform output -raw alb_url)
echo $ALB_URL

# Tester l'accès
curl $ALB_URL

# Vérifier la répartition de charge
for i in {1..5}; do curl -s $ALB_URL | grep Instance; done

# Voir les outputs
terraform output
```

---

## 5️⃣ Détruire (IMPORTANT!) (10 min)

```bash
# ⚠️ Après les tests, détruire pour économiser les crédits!

cd terraform/environments/dev
terraform destroy

# Puis détruire le bootstrap
cd ../bootstrap
terraform destroy
```

---

## 📚 Documentation complète

- **terraform/README.md** : Documentation Terraform complète
- **DEPLOYMENT_GUIDE.md** : Guide étape par étape avec images
- **COMPLETION_CHECKLIST.md** : Validation du projet

---

## 🔗 Fichiers clés

```
terraform/
├── bootstrap/              ← Backend S3 + DynamoDB
├── environments/dev/       ← Configuration DEV
├── modules/network/        ← VPC + Subnets
├── modules/security/       ← Security Groups + IAM
├── modules/load-balancer/  ← ALB
├── modules/compute/        ← EC2 + Auto Scaling
├── modules/database/       ← RDS PostgreSQL
├── modules/storage/        ← S3 Buckets
└── scripts/deploy.sh       ← Script de déploiement
```

---

## ✅ Points clés

✅ **Infrastructure as Code** - Toute l'infra en Terraform  
✅ **Multi-environnements** - dev/test/prod  
✅ **Haute disponibilité** - ALB + ASG + Multi-AZ (prod)  
✅ **Sécurité** - Subnets privés, Security Groups minimalistes  
✅ **CI/CD** - Pipeline GitHub Actions  
✅ **État distant** - Backend S3 + DynamoDB lock  

---

**Besoin d'aide ?** Voir `DEPLOYMENT_GUIDE.md` section "Dépannage"

**Prêt ?** Commencez par l'étape 1 ci-dessus ! 🚀
