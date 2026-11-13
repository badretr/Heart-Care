#!/usr/bin/env bash
#
# Bootstrap du backend distant Terraform.
#
# Cree, avant toute initialisation du projet principal :
#   - le bucket S3 qui heberge les fichiers d'etat (chiffre, versionne, prive) ;
#   - le bucket S3 qui recoit ses journaux d'acces ;
#   - la table DynamoDB de verrouillage (optionnelle : le backend utilise
#     use_lockfile, le verrouillage natif S3).
#
# Pourquoi un script et non la configuration Terraform de terraform/bootstrap/ ?
# Sur AWS Academy Learner Lab, une SCP d'organisation refuse
# s3:GetBucketObjectLockConfiguration. Le provider AWS appelle cette API a
# chaque lecture d'une ressource aws_s3_bucket, ce qui rend ces deux buckets
# impossibles a gerer avec Terraform dans cet environnement (create, import et
# refresh echouent tous sur cette lecture). La configuration Terraform reste
# fournie dans terraform/bootstrap/ : elle est la reference et s'applique telle
# quelle sur un compte AWS standard. Ce script est le chemin utilise dans le lab.
#
# Usage : ./scripts/bootstrap.sh [region]

set -euo pipefail

REGION="${1:-us-east-1}"
PROJECT="heartcare"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PROJECT}-terraform-state-${ACCOUNT_ID}"
LOGS_BUCKET="${PROJECT}-terraform-state-logs-${ACCOUNT_ID}"
LOCK_TABLE="${PROJECT}-terraform-lock"

echo "Compte AWS : ${ACCOUNT_ID}"
echo "Region     : ${REGION}"
echo

create_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo "  bucket ${bucket} : deja present"
  else
    if [ "$REGION" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$bucket" --region "$REGION" >/dev/null
    else
      aws s3api create-bucket --bucket "$bucket" --region "$REGION" \
        --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
    fi
    echo "  bucket ${bucket} : cree"
  fi

  # Versioning : permet de revenir a un etat anterieur (exigence 16.1).
  aws s3api put-bucket-versioning --bucket "$bucket" \
    --versioning-configuration Status=Enabled

  # Chiffrement au repos de l'etat Terraform (exigence 16.1 et 8).
  aws s3api put-bucket-encryption --bucket "$bucket" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

  # Aucun acces public : l'etat contient des donnees sensibles (exigence 8).
  aws s3api put-public-access-block --bucket "$bucket" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

  echo "  bucket ${bucket} : versioning, chiffrement et blocage public actifs"
}

echo "1. Bucket des journaux"
create_bucket "$LOGS_BUCKET"
echo
echo "2. Bucket d'etat"
create_bucket "$STATE_BUCKET"
echo
echo "3. Table de verrouillage DynamoDB (complement a use_lockfile)"
if aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then
  echo "  table ${LOCK_TABLE} : deja presente"
else
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --sse-specification Enabled=true >/dev/null
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE"
  echo "  table ${LOCK_TABLE} : creee"
fi

cat <<EOF

Backend pret. Reportez ces valeurs dans le bloc backend de chaque environnement :

  bucket       = "${STATE_BUCKET}"
  key          = "<dev|test|prod>/terraform.tfstate"
  region       = "${REGION}"
  encrypt      = true
  use_lockfile = true

Puis, dans terraform/environments/<env> : terraform init
EOF
