# Tests obligatoires

Les neuf tests de la section 22 du cahier des charges, leur procédure exacte et
le résultat constaté.

| # | Test | Attendu | Constaté |
|---|---|---|---|
| 1 | Format | Aucune différence | conforme |
| 2 | Validation | Success | conforme |
| 3 | Plan | Plan sans erreur | conforme |
| 4 | Accès Web | Page disponible | conforme |
| 5 | Répartition | Plusieurs hôtes observés | conforme |
| 6 | Panne | Service toujours disponible | conforme |
| 7 | Auto Scaling | Nombre d'instances adapté | conforme |
| 8 | Sécurité DB | Accès refusé | conforme |
| 9 | Destruction | Ressources supprimées | conforme |

---

## Test 1 — Format

```bash
cd /chemin/vers/Heart-Care-main
terraform fmt -check -recursive .
```

**Attendu :** aucune sortie, code de retour 0.

**Constaté :** aucune différence. La commande ne liste aucun fichier, ce qui
signifie que tous les `.tf` sont formatés selon la convention Terraform.

Le pipeline exécute la même commande et échoue si un fichier ne l'est pas.

---

## Test 2 — Validation

```bash
for e in dev test prod; do
  cd terraform/environments/$e
  terraform init -backend=false
  terraform validate
done
```

**Attendu :** `Success! The configuration is valid.`

**Constaté :**

```
dev    : Success! The configuration is valid.
test   : Success! The configuration is valid.
prod   : Success! The configuration is valid.
```

Les trois environnements valident, pas seulement celui qui est déployé.

---

## Test 3 — Plan

```bash
cd terraform/environments/dev
export TF_VAR_db_password='<mot-de-passe>'
terraform plan -refresh=false
```

**Attendu :** un plan sans erreur.

**Constaté :**

```
No changes. Your infrastructure matches the configuration.
```

Le plan est **stable** : exécuté plusieurs fois de suite sur une
infrastructure inchangée, il ne propose aucune modification. Ce n'était pas le
cas initialement — le tag `CreatedAt` utilisait `timestamp()`, ce qui faisait
apparaître une modification sur chaque ressource à chaque exécution. La valeur
provient désormais d'une variable fixe.

> `-refresh=false` contourne une SCP d'AWS Academy qui refuse
> `s3:GetBucketObjectLockConfiguration`. Sur un compte standard, retirer ce
> drapeau.

---

## Test 4 — Accès Web

```bash
cd terraform/environments/dev
curl -s -o /dev/null -w "%{http_code}\n" "$(terraform output -raw alb_url)"
curl -s "$(terraform output -raw alb_url)" | grep -oE "<title>[^<]*</title>"
```

**Attendu :** la page est disponible.

**Constaté :**

```
200
<title>Heart Care | Heart Hospital</title>
```

L'application Heart Care complète est servie — pages d'accueil, services,
médecins, galerie, prise de rendez-vous — et non une page de test.

**Capture à joindre :** le site ouvert dans un navigateur, sur l'URL de l'ALB.

---

## Test 5 — Répartition de charge

L'endpoint `/whoami`, servi directement par nginx, indique quelle instance a
traité la requête. L'en-tête `X-Served-By` porte la même information sur
**toutes** les réponses, y compris les pages de l'application.

```bash
URL=$(terraform output -raw alb_url)
for i in $(seq 1 10); do
  curl -s "$URL/whoami" | grep -oE "Instance : [a-z0-9.-]+"
done | sort | uniq -c
```

**Attendu :** plusieurs hôtes observés.

**Constaté :** sur 12 requêtes, exactement 6 par instance.

```
      6 Instance : ip-10-20-11-125     (us-east-1a)
      6 Instance : ip-10-20-12-118     (us-east-1b)
```

Même répartition sur l'en-tête de la page d'accueil :

```
      3 X-Served-By: ip-10-20-11-125
      3 X-Served-By: ip-10-20-12-118
```

Variante, en observant l'en-tête sur la page d'accueil :

```bash
for i in $(seq 1 10); do curl -sI "$URL" | grep -i x-served-by; done
```

**Capture à joindre :** la page `/whoami` actualisée plusieurs fois, montrant
des noms d'instance différents.

---

## Test 6 — Panne d'une instance

```bash
ASG=$(terraform output -raw autoscaling_group_name)
TG=$(terraform output -raw target_group_arn)

# Instances avant la panne
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[].{Id:InstanceId,AZ:AvailabilityZone}' --output table

# Arrêt brutal d'une instance, sans réduire la capacité souhaitée
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id <instance-id> --no-should-decrement-desired-capacity

# Le service répond-il pendant le remplacement ?
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code} " "$URL"; sleep 5
done
```

**Attendu :** le service reste disponible.

**Constaté :** l'instance `i-03977c24c9fd69b9b` (`us-east-1a`) a été arrêtée
brutalement, puis le service a été interrogé toutes les 5 secondes pendant
2 min 30 :

```
200 200 200 200 200 200 200 200 200 200 200 200 200 200 200
200 200 200 200 200 200 200 200 200 200 200 200 200 200 200

RESULTAT : 30 reponses 200, 0 erreurs
```

**Aucune requête n'a échoué.** L'ALB a cessé d'envoyer du trafic à l'instance
arrêtée, et l'Auto Scaling Group en a démarré une autre dans la même zone :

```
us-east-1a   i-05ea6aea6bd6f1394   InService   Healthy   <- remplaçante
us-east-1b   i-0a1e208eb9cfb7c70   InService   Healthy
```

Ce test a par ailleurs été rejoué à chaque mise à jour du `user_data` au cours
du projet, chaque remplacement ayant été fait une instance à la fois. Le
service n'a jamais été interrompu.

> `autoscaling:StartInstanceRefresh`, qui orchestrerait ce remplacement
> automatiquement, est refusé par une SCP d'AWS Academy. Le remplacement manuel
> instance par instance produit le même résultat.

**Capture à joindre :** la console EC2 pendant le remplacement, montrant
l'ancienne instance en `shutting-down` et la nouvelle en `pending`, pendant que
le site répond.

---

## Test 7 — Auto Scaling

```bash
ASG=$(terraform output -raw autoscaling_group_name)

# Capacité initiale
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}'

# Montée temporaire à 3 instances
aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG" --desired-capacity 3

# Vérifier l'ajout
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[].{Id:InstanceId,AZ:AvailabilityZone,State:LifecycleState}' \
  --output table

# Retour à la capacité nominale
aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG" --desired-capacity 2
```

**Attendu :** le nombre d'instances s'adapte.

**Constaté :** capacité initiale `Min=2, Max=3, Desired=2`. Après
`set-desired-capacity --desired-capacity 3`, l'ASG démarre une troisième
instance en moins d'une minute :

```
us-east-1a   i-05ea6aea6bd6f1394   InService
us-east-1b   i-0954fc80d895c5a07   InService   <- ajoutée
us-east-1b   i-0a1e208eb9cfb7c70   InService
```

Au retour à `--desired-capacity 2`, l'ASG en retire une, et le site continue de
répondre 200 pendant toute l'opération.

Des politiques de mise à l'échelle automatique sont également définies, pilotées
par deux alarmes CloudWatch sur l'utilisation processeur
(`cpu_high`, `cpu_low`). Le test manuel ci-dessus est volontaire : il est
reproductible en quelques minutes, là où déclencher l'alarme CPU demanderait de
générer une charge soutenue.

**Capture à joindre :** l'onglet *Activity* de l'ASG, montrant le lancement puis
la terminaison, et l'onglet *Instances* avec trois entrées.

---

## Test 8 — Sécurité de la base de données

```bash
DB=$(terraform output -raw db_instance_address)

# La base est-elle déclarée publique ?
aws rds describe-db-instances --db-instance-identifier heartcare-dev-db \
  --query 'DBInstances[0].{Public:PubliclyAccessible,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier}'

# Vers quelle adresse pointe l'endpoint ?
getent hosts "$DB"

# Tentative de connexion depuis Internet
timeout 15 bash -c "cat < /dev/null > /dev/tcp/$DB/5432" \
  && echo "CONNEXION ETABLIE" || echo "connexion refusee"
```

**Attendu :** accès refusé.

**Constaté :**

```
Public   : false
Subnets  : subnet-0044d6b91e07465e6, subnet-0f6d82766035a21ec   (sous-réseaux privés DB)
Endpoint : 10.20.21.169                                          (adresse privée)
Connexion: refusée
```

L'endpoint RDS résout vers une **adresse privée du VPC**. Aucune route ne mène
à ce sous-réseau depuis Internet, et le Security Group `sg-rds` n'accepte le
port 5432 que depuis le Security Group applicatif.

Trois barrières indépendantes protègent donc la base :

1. `publicly_accessible = false` ;
2. les sous-réseaux DB n'ont aucune route par défaut vers Internet ;
3. le Security Group n'autorise que `sg-app` en source.

**Capture à joindre :** la sortie de la commande, montrant l'adresse privée et
l'échec de connexion.

---

## Test 9 — Destruction

```bash
cd terraform/environments/dev
terraform destroy -refresh=false
```

**Attendu :** les ressources sont supprimées.

**Procédure recommandée pour la démonstration :**

```bash
# 1. Inventaire avant destruction
terraform state list | wc -l

# 2. Lire le plan de destruction avant de confirmer
terraform plan -destroy -refresh=false

# 3. Détruire
terraform destroy -refresh=false -auto-approve

# 4. Vérifier qu'il ne reste rien de facturable
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId' --output text
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
```

Les quatre dernières commandes doivent toutes renvoyer une sortie vide.

**À détruire en dernier**, et seulement si l'on veut repartir de zéro :

```bash
# Le bucket d'état et la table de verrouillage ne sont PAS gérés par destroy.
aws s3 rm s3://heartcare-terraform-state-<compte>/ --recursive
aws s3 rb s3://heartcare-terraform-state-<compte>
aws dynamodb delete-table --table-name heartcare-terraform-lock
```

> **Attention :** supprimer le bucket d'état supprime l'historique complet de
> l'infrastructure. À ne faire qu'une fois la soutenance terminée.

**À noter pour la démonstration :** la destruction prend une dizaine de
minutes, les NAT Gateways et l'instance RDS étant longues à supprimer. Comme
`skip_final_snapshot = true` et `deletion_protection = false` sont positionnés
sur RDS, aucune confirmation supplémentaire n'est demandée — c'est volontaire
pour cet environnement de démonstration, et à inverser en production.

**Capture à joindre :** la ligne finale `Destroy complete! N resources
destroyed.` et la console AWS vide.

---

## Tests complémentaires

Au-delà des neuf tests obligatoires.

### Le plan est stable

```bash
terraform apply -refresh=false -auto-approve
terraform plan  -refresh=false        # doit afficher "No changes"
```

Un plan non vide juste après un `apply` signale une valeur instable dans le
code — c'était le cas avec `timestamp()`.

### Aucun fichier sensible n'est versionné

```bash
git ls-files | grep -E "tfstate|\.terraform|tfplan|\.tfvars$"
```

**Attendu :** aucune sortie. Seul `terraform.tfvars.example`, sans valeur
sensible, est versionné.

### Aucun secret en clair dans le dépôt

```bash
git grep -nE "(aws_secret_access_key|AKIA[0-9A-Z]{16}|password\s*=\s*\"[^\"$])" -- '*.tf' '*.yml'
```

**Attendu :** aucune correspondance.

### L'accès public aux buckets est bloqué

```bash
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text); do
  echo "$b : $(aws s3api get-public-access-block --bucket "$b" \
    --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>&1)"
done
```

**Attendu :** `True` pour tous les buckets du projet.

### L'état distant est bien versionné

```bash
aws s3api list-object-versions \
  --bucket heartcare-terraform-state-<compte> --prefix dev/ \
  --query 'Versions[].{Id:VersionId,Date:LastModified}' --output table
```

**Attendu :** plusieurs versions, ce qui permet de restaurer un état antérieur.
