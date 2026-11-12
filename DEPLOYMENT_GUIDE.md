# 🚀 Guide Complet de Déploiement - Heart Care Infrastructure

**Créé le** : 2026-11-12  
**Environnement** : AWS (eu-west-1)  
**Budget** : $50 de crédit AWS  

---

## ⏰ Durée estimée
- Bootstrap : 5 minutes
- Déploiement DEV : 10-15 minutes
- Tests : 10 minutes
- **Total : ~30 minutes**

---

## 📋 Checklist pré-déploiement

- [ ] Compte AWS configuré et credentials en place
- [ ] Terraform installé (>= 1.6.0)
- [ ] AWS CLI v2 installé
- [ ] Git configuré
- [ ] Dépôt GitHub accessible
- [ ] Crédits AWS disponibles ($50)

---

## 🔑 Étape 1 : Configuration AWS

### 1.1 Vérifier les credentials

```bash
# Vérifier AWS CLI
aws sts get-caller-identity

# Résultat attendu :
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

### 1.2 Définir la région par défaut

```bash
export AWS_REGION=eu-west-1
aws ec2 describe-regions --region-names eu-west-1
```

---

## 🔧 Étape 2 : Initialiser le Git Repo

```bash
cd /home/terraform/Desktop/Heart-Care-main

# Vérifier que Git est initialisé
git status

# Sinon initialiser
git init

# Configurer l'identité
git config user.email "votre@email.com"
git config user.name "Votre Nom"

# Ajouter les fichiers
git add terraform/ .github/ DEPLOYMENT_GUIDE.md
git commit -m "Initial Terraform infrastructure setup"
```

---

## 🏗️ Étape 3 : Bootstrap du Backend

### 3.1 Créer les ressources de backend

```bash
cd terraform/bootstrap

# Rendre les scripts exécutables
chmod +x ../scripts/*.sh

# Lancer le bootstrap
bash ../scripts/bootstrap.sh eu-west-1
```

**Output attendu :**
```
==================================
Heart Care Terraform Bootstrap
==================================
AWS Region: eu-west-1
AWS Account ID: 123456789012

✅ terraform.tfvars created
🔄 Running terraform init...
📝 Running terraform apply...
✅ Bootstrap complete!

🔑 Terraform Backend Configuration:
======================================
bucket         = "heartcare-terraform-state-123456789012"
key            = "dev/terraform.tfstate"
region         = "eu-west-1"
encrypt        = true
dynamodb_table = "heartcare-terraform-lock"

[Continuer jusqu'à la fin...]
```

### 3.2 Copier le nom du bucket

À partir de la sortie ci-dessus, note le `bucket_name` :
```bash
export BUCKET_NAME=heartcare-terraform-state-123456789012
echo $BUCKET_NAME
```

---

## 💻 Étape 4 : Déployer l'environnement DEV

### 4.1 Initialiser l'environnement

```bash
cd ../environments/dev

# Créer terraform.tfvars
cp terraform.tfvars.example terraform.tfvars

# Éditer le fichier
nano terraform.tfvars

# IMPORTANT : Changer le db_password !
# Chercher la ligne : db_password = "ChangeMe123!"
# Et remplacer par un mot de passe sécurisé (8+ caractères, avec majuscules, chiffres, symboles)
```

### 4.2 Initialiser Terraform avec le backend distant

```bash
# Remplacer BUCKET_NAME par la valeur obtenue à l'étape 3.2
terraform init \
  -backend-config=bucket=$BUCKET_NAME \
  -backend-config=key=dev/terraform.tfstate \
  -backend-config=region=eu-west-1 \
  -backend-config=encrypt=true \
  -backend-config=dynamodb_table=heartcare-terraform-lock

# Répondre 'yes' quand demandé
```

### 4.3 Valider la configuration

```bash
# Format check
terraform fmt -check -recursive ../..

# Validate
terraform validate

# Résultat attendu : Success! The configuration is valid.
```

### 4.4 Créer le plan de déploiement

```bash
# Afficher le plan
terraform plan -out=tfplan

# Cela affichera tous les ressources à créer (~30-50 ressources)
# Vérifier qu'il n'y a pas d'erreurs
```

### 4.5 Déployer les ressources

```bash
# ATTENTION : Cela crée des ressources AWS réelles !
terraform apply tfplan

# Cela prendra 10-15 minutes
# Attendre le message : Apply complete! Resources: XX added, 0 changed, 0 destroyed.
```

---

## 🎯 Étape 5 : Vérifier le déploiement

### 5.1 Récupérer les outputs

```bash
# Voir tous les outputs
terraform output

# Ou obtenir des valeurs spécifiques
ALB_URL=$(terraform output -raw alb_url)
echo "URL de l'application : $ALB_URL"

# Autres informations utiles
terraform output alb_dns_name
terraform output autoscaling_group_name
terraform output db_endpoint
```

### 5.2 Attendre que les instances se lancent

```bash
# Les instances prennent 3-5 minutes pour devenir saines
# Vérifier le statut

ALB_URL=$(terraform output -raw alb_url)

# Vérifier l'ALB Target Group
AWS_REGION=eu-west-1
TARGET_GROUP=$(terraform output -raw target_group_arn | awk -F: '{print $NF}')

aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:eu-west-1:$(aws sts get-caller-identity --query Account --output text):$TARGET_GROUP" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table
```

**Résultat attendu :**
```
Instance-1  healthy
Instance-2  healthy
```

### 5.3 Tester l'application

```bash
# Test simple
curl $ALB_URL

# Réponse attendue : page HTML avec "Heart Care" ou "Health Check OK"

# Test avec visualisation de l'instance
for i in {1..5}; do
  echo "=== Requête $i ==="
  curl -s $ALB_URL | grep Instance || echo "Instance non visible"
  sleep 2
done

# Les instances peuvent varier, prouvant que le load balancer fonctionne
```

### 5.4 Vérifier la base de données

```bash
# Obtenir les informations de la DB
DB_HOST=$(terraform output -raw db_endpoint | cut -d: -f1)
DB_USER=$(terraform output db_username)

echo "Host: $DB_HOST"
echo "User: $DB_USER"
echo "Database: heartcare"

# Essayer de se connecter (optionnel - nécessite psql)
# psql -h $DB_HOST -U $DB_USER -d heartcare
```

### 5.5 Vérifier les Security Groups

```bash
# Les instances ne doivent pas être accessibles directement
# Seules les requêtes via le Load Balancer fonctionnent

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw autoscaling_group_name)" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --region eu-west-1)

echo "Instance ID: $INSTANCE_ID"

# Les instances devraient avoir une IP privée, pas d'IP élastique
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].[PrivateIpAddress,PublicIpAddress]' \
  --output text \
  --region eu-west-1
```

---

## ✅ Étape 6 : Exécuter les tests

### 6.1 Test de répartition de charge

```bash
# Afficher plusieurs fois le nom d'hôte
for i in {1..10}; do
  curl -s $ALB_URL | grep -o "Instance: [^<]*" || echo "Instance non visible"
done

# Les noms devraient alterner entre plusieurs instances
# Cela prouve que le load balancer fonctionne
```

### 6.2 Test d'Auto Scaling (optionnel)

```bash
# Récupérer le nom du Auto Scaling Group
ASG_NAME=$(terraform output -raw autoscaling_group_name)
echo "ASG: $ASG_NAME"

# Voir les instances actuelles
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,Instances]' \
  --output text

# Augmenter temporairement (optionnel - coûts!)
# aws autoscaling set-desired-capacity \
#   --auto-scaling-group-name $ASG_NAME \
#   --desired-capacity 3

# Ramener à 2
# aws autoscaling set-desired-capacity \
#   --auto-scaling-group-name $ASG_NAME \
#   --desired-capacity 2
```

### 6.3 Test de panne (optionnel)

```bash
# Simuler la panne d'une instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw autoscaling_group_name)" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Arrêt de l'instance : $INSTANCE_ID"
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Attendre 30-60 secondes
# L'Auto Scaling Group devrait relancer une nouvelle instance

# Vérifier que le service continue de répondre
for i in {1..5}; do
  curl -s $ALB_URL > /dev/null && echo "✓ Service disponible" || echo "✗ Service indisponible"
  sleep 10
done

# Relancer l'instance (optionnel)
# aws ec2 start-instances --instance-ids $INSTANCE_ID
```

---

## 💾 Étape 7 : Sauvegarde et Documentation

### 7.1 Commit les configurations

```bash
# Retourner à la racine du projet
cd /home/terraform/Desktop/Heart-Care-main

# Ajouter et committer
git add terraform/ .github/ DEPLOYMENT_GUIDE.md
git commit -m "Deployed Heart Care infrastructure to DEV environment"

# Voir les modifications
git log -1 --stat
```

### 7.2 Créer un fichier de notes

```bash
# Créer un fichier de notes
cat > DEPLOYMENT_NOTES.md << 'EOF'
# Notes de déploiement

## Date : $(date)

### Environnement DEV
- **ALB URL** : $ALB_URL
- **Region** : eu-west-1
- **Bucket State** : $BUCKET_NAME
- **Status** : ✅ Opérationnel

### Ressources créées
- VPC avec 6 subnets (2 publics, 2 privés app, 2 privés DB)
- Application Load Balancer avec Target Group
- Auto Scaling Group (2 instances)
- RDS PostgreSQL
- S3 Buckets (app + logs)

### Prochaines étapes
- [ ] Configurer le monitoring CloudWatch
- [ ] Ajouter HTTPS/SSL
- [ ] Configurer les alertes SNS
- [ ] Documenter les procédures d'urgence

### Commandes utiles
EOF

# Remplir avec les valeurs réelles
echo "ALB_URL=$ALB_URL" >> DEPLOYMENT_NOTES.md
echo "BUCKET=$BUCKET_NAME" >> DEPLOYMENT_NOTES.md
```

---

## ⚠️ Important : Gestion des coûts

### Coûts estimés (DEV seul)
- EC2 t3.micro (2x) : $8/mois
- RDS db.t3.micro : $8/mois
- ALB : $16/mois
- Data Transfer : $2/mois
- **Total : ~$34/mois**

### Économiser de l'argent
```bash
# Arrêter les instances quand pas utilisé
aws ec2 stop-instances --instance-ids <instance-id>

# Mais cela ne sauvegarde pas sur RDS et ALB

# Meilleure solution : Détruire complètement après les tests !
```

---

## 🗑️ Destruction (IMPORTANT!)

⚠️ **Si vous avez fini les tests, détruire immédiatement pour économiser les crédits !**

### Étape 1 : Détruire DEV

```bash
cd terraform/environments/dev

# Voir ce qui sera supprimé
terraform plan -destroy

# Supprimer (demande confirmation)
terraform destroy

# Ou via le script
bash ../../scripts/deploy.sh dev destroy
```

### Étape 2 : Détruire le bootstrap (dernier)

```bash
cd ../bootstrap

terraform destroy
```

---

## 📊 Résumé du déploiement

| Étape | Durée | Action |
|-------|-------|--------|
| 1. Configuration AWS | 2 min | Vérifier credentials |
| 2. Git Setup | 2 min | Initialiser repo |
| 3. Bootstrap | 5 min | Créer S3 + DynamoDB |
| 4. Déploiement DEV | 15 min | terraform apply |
| 5. Vérification | 5 min | Tests et outputs |
| 6. Tests | 10 min | Répartition, etc. |
| **Total** | **~40 min** | |

---

## 🐛 Dépannage rapide

### Problème : "Access Denied" lors du bootstrap

**Solution :**
```bash
# Vérifier les credentials
aws sts get-caller-identity

# Vérifier les permissions (vous avez besoin de S3, DynamoDB, IAM)
aws iam get-user
```

### Problème : Les instances ne sont pas saines

**Solution :**
```bash
# Vérifier les logs
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw autoscaling_group_name)" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Voir les logs du user_data
aws ssm start-session --target $INSTANCE_ID
tail -f /var/log/user-data.log
```

### Problème : "State lock timeout"

**Solution :**
```bash
# Attendre quelques minutes (le verrou se libère automatiquement)
# Ou forcer le déverrouillage :

aws dynamodb delete-item \
  --table-name heartcare-terraform-lock \
  --key '{"LockID":{"S":"heartcare-dev"}}'
```

---

## 🎓 Points d'apprentissage

Ce déploiement démontre :

1. **Infrastructure as Code** : Toute l'infrastructure est définie en code
2. **Modularité** : Réutilisation de modules pour dev/test/prod
3. **État distant** : Backend S3 sécurisé avec verrous DynamoDB
4. **CI/CD** : Pipeline GitHub Actions automatisé
5. **Sécurité** : Subnets privés, Security Groups, chiffrement
6. **Scalabilité** : Auto Scaling Groups et Load Balancer
7. **Monitoring** : CloudWatch alarms et metrics

---

## 📞 Support

En cas de problème :

1. Vérifier la section [Dépannage](#dépannage-rapide)
2. Consulter les logs :
   ```bash
   # Logs du déploiement
   terraform show
   
   # Logs des instances
   aws ec2 describe-instances --query 'Reservations[*].Instances[*].Tags'
   ```
3. Créer une issue sur GitHub

---

**✨ Bon déploiement ! ✨**

Vous avez maintenant une infrastructure Cloud moderne, sécurisée et scalable pour l'application Heart Care !
