# Présentation de soutenance

**Projet Terraform et CI/CD — Infrastructure Cloud Heart Care**

Support de 14 diapositives, prévu pour 15 à 20 minutes, suivi de la
démonstration en direct. Les notes de passage figurent sous chaque diapositive.

---

## Diapositive 1 — Titre

> **Heart Care — Infrastructure Cloud avec Terraform et CI/CD**
> Déploiement automatisé d'une application Django sur AWS
> Mohamed Badreddine Trabelsi — Parcours Cloud et Réseaux

*Notes :* annoncer d'emblée que l'application déployée est une application
Django réelle, pas une page de test. C'est le choix qui structure tout le reste.

---

## Diapositive 2 — Le besoin

Trois contraintes :

- l'application doit rester disponible si une instance tombe ;
- les instances et la base ne doivent jamais être joignables depuis Internet ;
- toute l'infrastructure doit être décrite en code, reproductible en trois
  environnements.

Budget : **50 $** de crédit AWS Academy.

*Notes :* la contrainte budgétaire n'est pas un détail — elle a dicté des
arbitrages réels, notamment sur les NAT Gateways.

---

## Diapositive 3 — Architecture

Reprendre le schéma de [architecture.md](architecture.md).

| Étage | Sous-réseaux | Exposition |
|---|---|---|
| Public | `10.20.1.0/24`, `10.20.2.0/24` | Internet entrant — ALB seul |
| Applicatif privé | `10.20.11.0/24`, `10.20.12.0/24` | Sortant via NAT |
| Base de données | `10.20.21.0/24`, `10.20.22.0/24` | Aucune |

Chaque étage dupliqué sur `us-east-1a` et `us-east-1b`.

*Notes :* insister sur le fait que les sous-réseaux de base n'ont **aucune
route par défaut** — une barrière indépendante des Security Groups.

---

## Diapositive 4 — Sécurité : la chaîne des Security Groups

```
Internet --80/443--> sg-alb --8000--> sg-app --5432--> sg-rds
```

Chaque règle désigne un **Security Group source**, jamais une plage CIDR.

*Notes :* une instance ne joint la base que parce qu'elle porte le SG
applicatif, pas parce qu'elle est dans un certain sous-réseau. La règle reste
juste si le plan d'adressage change.

---

## Diapositive 5 — Sécurité : secrets et chiffrement

| Donnée | Protection |
|---|---|
| Mot de passe RDS | `TF_VAR_db_password` → coffre GitHub → SSM `SecureString` |
| État Terraform | S3 chiffré AES256, versionné, verrou natif |
| Base RDS | `storage_encrypted = true` |
| Buckets S3 | AES256, accès public bloqué sur les quatre verrous |

**Aucun secret dans le dépôt.** Vérifiable : `git grep` sur les motifs de clés
ne renvoie rien.

---

## Diapositive 6 — Le code : sept modules

```
modules/  network · security · iam · load-balancer · compute · database · storage
environments/  dev · test · prod     (modules communs, variables distinctes)
```

Chaque module : `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
`README.md`. 158 variables, 158 descriptions, 12 validations.

*Notes :* le module `iam` ne figurait pas dans le découpage proposé. Il a été
séparé pour une raison technique — expliquée diapositive 9.

---

## Diapositive 7 — Le pipeline CI/CD

| Déclencheur | Ce qui s'exécute |
|---|---|
| Pull Request | `fmt` → `init` → `validate` → `plan` **sur les trois environnements**, plans publiés en artefact |
| Push sur `master` | idem, puis **`apply` sur `dev` uniquement** |
| Déclenchement manuel | `apply` sur `test` ou `prod`, **bloqué jusqu'à approbation d'un relecteur** |

*Notes :* montrer les deux runs côte à côte — sur un push, le job `test/prod`
est ignoré ; en manuel, c'est l'inverse. Les deux jobs sont exclusifs.

---

## Diapositive 8 — Résultats des tests

| Test | Résultat |
|---|---|
| Format, validation, plan | conformes, plan stable |
| Accès Web | HTTP 200, application Heart Care |
| Répartition | 6/6 entre les deux zones |
| **Panne d'une instance** | **30 requêtes, 30 × HTTP 200, 0 erreur** |
| Auto Scaling | 2 → 3 → 2 |
| Sécurité DB | endpoint = `10.20.21.169`, connexion refusée |

*Notes :* le test de panne est le résultat le plus parlant. Arrêt brutal d'une
instance, interrogation toutes les 5 secondes pendant 2 min 30 : aucune
requête perdue.

---

## Diapositive 9 — Les contraintes AWS Academy

Trois SCP d'organisation, identifiées **en testant chaque action une par une** :

| Refusé | Conséquence | Contournement |
|---|---|---|
| `iam:CreateRole`, `AttachRolePolicy` | politique créée mais non rattachée | `create_iam_role` ; `true` sur compte standard |
| `iam:TagPolicy`, `TagInstanceProfile` | ressources IAM non taguables | provider aliasé `aws.untagged` |
| `s3:GetBucketObjectLockConfiguration` | toute relecture de bucket échoue | `-refresh=false` + `ignore_changes` sur les tags |

*Notes :* le blocage n'était pas « IAM en bloc ». `CreatePolicy`,
`CreateInstanceProfile` et `AddRoleToInstanceProfile` sont autorisées — la
politique de moindre privilège est réellement déployée.

---

## Diapositive 10 — L'erreur qui a coûté le plus cher

Nous avions conclu que **le backend S3 était impossible** et étions passés à un
backend local, contredisant l'exigence 16.

C'était faux. Le SCP bloque `GetObjectLockConfiguration`, appelée par le
provider sur une *ressource* `aws_s3_bucket` — **jamais par le backend**, qui
n'utilise que `GetObject`, `PutObject` et `ListObjects`.

*Notes :* un `AccessDenied` sur une API S3 avait été généralisé à « S3 est
bloqué ». Le test qui l'a démenti coûtait cinq minutes. Leçon : un message
d'autorisation ne dit pas ce qui est bloqué, seulement quelle API a été
refusée.

---

## Diapositive 11 — Déployer une application réelle

Trois problèmes qu'une page de test n'aurait jamais révélés :

1. **Conflit de ports** — nginx et gunicorn tous deux sur 8000 → `502`.
2. **`DEBUG = True`** — traces d'exception et routes exposées à tout visiteur.
3. **Manifeste de fichiers statiques** — un template référence un fichier
   inexistant ; en production, erreur 500 sur **toutes** les pages.

*Notes :* le 3 n'est apparu qu'en corrigeant le 2. Activer un réglage de
sécurité révèle souvent des défauts préexistants — le réflexe est de corriger
le défaut, pas de désactiver le réglage.

---

## Diapositive 12 — Coûts

**≈ 0,18 $/h**, soit 127 $/mois en continu. Le crédit de 50 $ couvre
**~285 heures**.

| Poste | Part |
|---|---:|
| NAT Gateways (×2) | 52 % |
| Load Balancer | 13 % |
| Instances EC2 (×2) | 12 % |

*Notes :* les EC2, qu'on imagine au centre du coût, ne pèsent que 12 %. Deux
NAT au lieu d'une coûtent 33 $/mois de plus — assumé : une seule ferait de sa
zone un point de défaillance unique.

---

## Diapositive 13 — Ce qui reste ouvert

- Moindre privilège IAM **écrit mais non appliqué** à l'exécution (SCP).
- ALB en HTTP tant qu'aucun certificat n'est fourni — listener HTTPS codé.
- `-refresh=false` : la dérive manuelle dans la console n'est pas détectée.

*Notes :* les annoncer soi-même. Un jury repère ce qu'on cache ; il crédite ce
qu'on assume.

---

## Diapositive 14 — Démonstration

1. Le site en ligne, puis `/whoami` actualisé → deux instances.
2. Arrêt d'une instance → le site continue de répondre.
3. Le pipeline sur GitHub Actions → plan lisible, apply conditionné.
4. L'état distant sur S3 → chiffré, versionné.
5. **`terraform destroy`** → tout est supprimé.

---

## Déroulé de la démonstration

### Avant de commencer

```bash
aws sts get-caller-identity          # la session Learner Lab est-elle valide ?
cd terraform/environments/dev
terraform plan -refresh=false        # doit afficher « No changes »
```

> Les identifiants AWS Academy expirent à chaque session. S'ils ont tourné,
> les recopier dans `~/.aws/credentials` **et** dans les secrets GitHub, sinon
> le pipeline échoue en direct.

### 1. Le site et la répartition

```bash
URL=$(terraform output -raw alb_url); echo $URL
for i in $(seq 1 10); do curl -s "$URL/whoami" | grep -oE "Instance : [a-z0-9.-]+"; done | sort | uniq -c
```

### 2. Le test de panne

```bash
ASG=$(terraform output -raw autoscaling_group_name)
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id <id> --no-should-decrement-desired-capacity

for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code} " "$URL"; sleep 5; done
```

Attendu : trente fois `200`.

### 3. La base est injoignable

```bash
DB=$(terraform output -raw db_endpoint | cut -d: -f1)
getent hosts $DB                     # adresse privée 10.20.21.x
timeout 10 bash -c "cat </dev/null >/dev/tcp/$DB/5432" || echo "refusé"
```

### 4. La destruction

```bash
terraform plan -destroy -refresh=false   # lire le plan avant de confirmer
terraform destroy -refresh=false
```

Puis vérifier qu'il ne reste rien de facturable :

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId' --output text
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text
```

Les trois doivent renvoyer une sortie vide.

---

## Questions probables

**« Pourquoi deux NAT Gateways alors que c'est 52 % du coût ? »**
Une seule ferait de sa zone un point de défaillance unique pour tout le trafic
sortant. 33 $/mois ne justifient pas de dégrader la propriété que le projet
doit démontrer.

**« Le moindre privilège, il sert à quoi s'il n'est pas appliqué ? »**
La politique est réellement créée et visible dans la console. Seul
l'attachement au rôle est refusé par une SCP. `create_iam_role = true` suffit
sur un compte standard — aucune autre modification.

**« Pourquoi `-refresh=false` ? »**
Une SCP refuse la lecture de la configuration object-lock des buckets. Le
compromis assumé : Terraform ne détecte pas une dérive introduite à la main
dans la console.

**« Qu'est-ce qui vous a le plus appris ? »**
Avoir abandonné le backend S3 pendant plusieurs jours sur la foi d'un
`AccessDenied` qui ne le concernait pas. Un message d'autorisation nomme une
API refusée, pas une fonctionnalité impossible.

**« Et si le pipeline échoue pendant la démonstration ? »**
La cause la plus probable est l'expiration des identifiants Learner Lab, qui
vivent dans les secrets GitHub. La procédure est au point 10 du README.
