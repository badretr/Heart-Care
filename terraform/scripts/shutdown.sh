#!/usr/bin/env bash
#
# Ferme un environnement : detruit toutes ses ressources facturables, puis
# verifie qu'il ne reste rien.
#
# A lancer des qu'on arrete de travailler. L'infrastructure coute environ
# 0,17 $/h qu'elle serve ou non, soit plus de 4 $ par jour : un week-end
# oublie coute une douzaine de dollars.
#
# Ce qui N'EST PAS detruit, et c'est voulu :
#   - le bucket S3 de l'etat Terraform et son historique de versions ;
#   - son bucket de journaux ;
#   - la table DynamoDB de verrouillage.
# Ces trois-la coutent quelques centimes par mois et contiennent la memoire du
# projet. Les supprimer obligerait a tout reconstruire depuis zero.
#
# Usage : ./scripts/shutdown.sh [dev|test|prod]        (defaut : dev)
#         ./scripts/shutdown.sh dev --oui              (sans confirmation)

set -euo pipefail

ENVIRONNEMENT="${1:-dev}"
SANS_CONFIRMATION="${2:-}"
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOSSIER="${RACINE}/environments/${ENVIRONNEMENT}"

if [ ! -d "$DOSSIER" ]; then
  echo "Environnement inconnu : ${ENVIRONNEMENT}" >&2
  echo "Valeurs possibles : dev, test, prod" >&2
  exit 1
fi

echo "=== Fermeture de l'environnement ${ENVIRONNEMENT} ==="
echo

# 1. La session AWS Academy expire a chaque fois : verifier avant tout.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  cat >&2 <<'FIN'
Les identifiants AWS sont expires ou absents.

Recopier le bloc « AWS Details -> AWS CLI » du Learner Lab dans
~/.aws/credentials, puis relancer ce script.
FIN
  exit 1
fi
echo "Compte AWS : $(aws sts get-caller-identity --query Account --output text)"
echo

cd "$DOSSIER"

# 2. Terraform exige toutes ses variables, meme pour detruire. Le mot de passe
#    n'est pas versionne : on le relit depuis SSM, ou on le demande.
if [ -z "${TF_VAR_db_password:-}" ]; then
  TF_VAR_db_password="$(aws ssm get-parameter \
    --name "/heartcare/${ENVIRONNEMENT}/db/password" --with-decryption \
    --query Parameter.Value --output text 2>/dev/null || true)"
  if [ -z "$TF_VAR_db_password" ]; then
    read -rsp "Mot de passe de la base (introuvable dans SSM) : " TF_VAR_db_password
    echo
  else
    echo "Mot de passe relu depuis SSM Parameter Store."
  fi
  export TF_VAR_db_password
fi

terraform init -input=false >/dev/null

NB="$(terraform state list 2>/dev/null | wc -l)"
if [ "$NB" -eq 0 ]; then
  echo "L'environnement ${ENVIRONNEMENT} ne contient aucune ressource : rien a detruire."
  exit 0
fi

echo
echo "=== Plan de destruction ==="
# -refresh=false contourne la SCP AWS Academy qui refuse la lecture de la
# configuration object lock des buckets S3.
terraform plan -destroy -refresh=false -input=false -no-color | tail -20

if [ "$SANS_CONFIRMATION" != "--oui" ]; then
  echo
  read -rp "Detruire ces ressources ? Taper « oui » pour confirmer : " REPONSE
  [ "$REPONSE" = "oui" ] || { echo "Annule. Rien n'a ete detruit."; exit 0; }
fi

echo
echo "=== Destruction en cours (compter une dizaine de minutes) ==="
terraform destroy -refresh=false -input=false -auto-approve

echo
echo "=== Verification : plus rien ne doit facturer ==="
RESTE=0
verifier() {
  local libelle="$1"; shift
  local trouve; trouve="$("$@" 2>/dev/null || true)"
  if [ -n "$trouve" ] && [ "$trouve" != "None" ]; then
    echo "  RESTE  ${libelle} : ${trouve}"
    RESTE=1
  else
    echo "  vide   ${libelle}"
  fi
}

verifier "instances EC2" aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text
verifier "NAT Gateways" aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output text
verifier "bases RDS" aws rds describe-db-instances \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
verifier "Load Balancers" aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerName' --output text
verifier "adresses IP publiques" aws ec2 describe-addresses \
  --query 'Addresses[].PublicIp' --output text

echo
if [ "$RESTE" -eq 0 ]; then
  cat <<FIN
Environnement ${ENVIRONNEMENT} ferme. Plus aucune ressource ne facture.

Conserves volontairement, pour quelques centimes par mois :
  - l'etat Terraform et son historique sur S3 ;
  - la table de verrouillage DynamoDB.

Pour reprendre :
  cd terraform/environments/${ENVIRONNEMENT}
  export TF_VAR_db_password='<mot-de-passe>'
  terraform apply -refresh=false
FIN
else
  cat >&2 <<FIN
ATTENTION : des ressources facturent encore (voir « RESTE » ci-dessus).

Elles appartiennent peut-etre a un autre environnement. Verifier leurs tags :
  aws ec2 describe-instances --query 'Reservations[].Instances[].Tags'
FIN
  exit 1
fi
