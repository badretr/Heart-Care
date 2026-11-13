# Heart Care — Infrastructure Cloud avec Terraform et CI/CD

Déploiement automatisé de l'application Web **Heart Care** (Django) sur AWS :
infrastructure modulaire et reproductible décrite avec Terraform, déployable en
trois environnements, et validée par un pipeline CI/CD avant toute application.

---

## 1. Architecture

L'application est accessible depuis Internet par un Application Load Balancer,
seul composant exposé. Les instances applicatives et la base de données sont
isolées dans des sous-réseaux privés, répartis sur deux zones de disponibilité.

```
                            Internet
                               │
                        ┌──────▼──────┐
                        │     ALB     │   sous-réseaux publics
                        │   port 80   │   10.20.1.0/24 · 10.20.2.0/24
                        └──────┬──────┘
                   ┌───────────┴───────────┐
          ┌────────▼────────┐     ┌────────▼────────┐
          │  EC2 t3.micro   │     │  EC2 t3.micro   │   sous-réseaux
          │  nginx :8000    │     │  nginx :8000    │   applicatifs privés
          │  gunicorn :8001 │     │  gunicorn :8001 │   10.20.11.0/24
          │  us-east-1a     │     │  us-east-1b     │   10.20.12.0/24
          └────────┬────────┘     └────────┬────────┘
                   └───────────┬───────────┘
                        ┌──────▼──────┐
                        │     RDS     │   sous-réseaux DB privés
                        │ PostgreSQL  │   10.20.21.0/24 · 10.20.22.0/24
                        │   port 5432 │   aucune route Internet
                        └─────────────┘
```

Le schéma détaillé, avec les flux, les Security Groups et le routage, se trouve
dans **[docs/architecture.md](docs/architecture.md)**.

### Plan d'adressage

| Composant | CIDR | Zone |
|---|---|---|
| VPC | `10.20.0.0/16` | — |
| Subnet public A | `10.20.1.0/24` | `us-east-1a` |
| Subnet public B | `10.20.2.0/24` | `us-east-1b` |
| Subnet privé App A | `10.20.11.0/24` | `us-east-1a` |
| Subnet privé App B | `10.20.12.0/24` | `us-east-1b` |
| Subnet privé DB A | `10.20.21.0/24` | `us-east-1a` |
| Subnet privé DB B | `10.20.22.0/24` | `us-east-1b` |

---

## 2. Prérequis

### Logiciels

> Terraform **1.10 au minimum** : le backend distant utilise `use_lockfile`,
> le verrouillage natif S3, qui n'existe pas avant cette version. Le pipeline
> installe la même version que le poste de développement (1.17.2).

| Outil | Version | Vérification |
|---|---|---|
| Terraform | ≥ 1.10.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| Git | ≥ 2.30 | `git --version` |

### Côté AWS

- Un compte AWS avec les droits de créer VPC, EC2, RDS, ELB, S3 et IAM.
- Région `us-east-1` (modifiable par la variable `aws_region`).
- Un bucket S3 pour l'état Terraform, créé par le script de bootstrap.

> **AWS Academy Learner Lab** : la région est limitée à `us-east-1` ou
> `us-west-2`, les identifiants sont temporaires et expirent à chaque session,
> et certaines actions IAM et S3 sont refusées par des SCP. Les contournements
> sont décrits en [section 9](#9-limites-connues).

---

## 3. Authentification, sans secret en clair

**Aucun identifiant ne doit être écrit dans le dépôt.** Trois chemins, selon le
contexte.

### En local

```bash
aws configure          # identifiants permanents
```

Sur AWS Academy, les identifiants sont temporaires : copier le bloc fourni par
le bouton **AWS Details → AWS CLI** du Learner Lab dans `~/.aws/credentials`.
Ils comportent un `aws_session_token` et expirent à la fin de la session.

Vérifier avant toute commande Terraform :

```bash
aws sts get-caller-identity
```

### Mot de passe de la base

Il est passé par variable d'environnement, jamais par fichier versionné :

```bash
export TF_VAR_db_password='<mot-de-passe>'
```

### Dans le pipeline

Les valeurs vivent dans **Settings → Secrets and variables → Actions** du dépôt
GitHub :

| Secret | Contenu |
|---|---|
| `AWS_ACCESS_KEY_ID` | Clé d'accès |
| `AWS_SECRET_ACCESS_KEY` | Clé secrète |
| `AWS_SESSION_TOKEN` | Jeton de session (identifiants temporaires) |
| `TF_VAR_DB_PASSWORD` | Mot de passe RDS |

GitHub masque automatiquement ces valeurs dans les journaux d'exécution.

---

## 4. Déploiement

### 4.1 Créer le backend distant, une seule fois

```bash
cd terraform
./scripts/bootstrap.sh us-east-1
```

Le script crée le bucket d'état (chiffré, versionné, privé), son bucket de
journaux et la table de verrouillage, puis affiche les valeurs à reporter dans
le bloc `backend` de chaque environnement.

### 4.2 Déployer un environnement

```bash
cd terraform/environments/dev

export TF_VAR_db_password='<mot-de-passe>'

terraform init                       # init + backend distant
terraform fmt -check -recursive ../..
terraform validate
terraform plan  -refresh=false -out=tfplan
terraform apply -refresh=false tfplan
```

L'URL du site s'affiche à la fin :

```bash
terraform output alb_url
```

Comptez une dizaine de minutes : la création des NAT Gateways et de l'instance
RDS est longue, et le `user_data` installe ensuite l'application.

> **Pourquoi `-refresh=false` ?** Une SCP d'AWS Academy refuse
> `s3:GetBucketObjectLockConfiguration`, que le provider appelle en relisant
> toute ressource `aws_s3_bucket`. Sur un compte AWS standard, retirez ce
> drapeau — voir [section 9](#9-limites-connues).

### 4.3 Détruire

```bash
cd terraform/environments/dev
terraform destroy -refresh=false
```

**À faire dès la fin de la démonstration** : l'infrastructure coûte environ
0,18 $ par heure, qu'elle serve ou non.

---

## 5. Les modules

Chaque module a son propre README, avec ses entrées, ses sorties et un exemple.

| Module | Rôle | Documentation |
|---|---|---|
| `network` | VPC, sous-réseaux, IGW, NAT, routage | [README](terraform/modules/network/README.md) |
| `security` | Security Groups en chaîne, paramètre SSM | [README](terraform/modules/security/README.md) |
| `iam` | Politique de moindre privilège, instance profile | [README](terraform/modules/iam/README.md) |
| `load-balancer` | ALB, listener, target group, health checks | [README](terraform/modules/load-balancer/README.md) |
| `compute` | Launch Template, `user_data`, ASG, politiques | [README](terraform/modules/compute/README.md) |
| `database` | RDS PostgreSQL, subnet group, paramètres | [README](terraform/modules/database/README.md) |
| `storage` | S3, versioning, chiffrement, cycle de vie | [README](terraform/modules/storage/README.md) |

### Arborescence

```
Heart-Care-main/
├── .github/workflows/terraform.yml   pipeline CI/CD
├── terraform/
│   ├── bootstrap/                    backend distant (référence Terraform)
│   ├── scripts/bootstrap.sh          backend distant (chemin Learner Lab)
│   ├── modules/                      7 modules réutilisables
│   └── environments/{dev,test,prod}/ un état et des variables par environnement
├── docs/                             architecture, sécurité, coûts, tests
├── hospital/ appointment/ heartcare/ application Django
└── README.md
```

---

## 6. Variables et sorties

### Variables principales

| Variable | Défaut `dev` | Description |
|---|---|---|
| `aws_region` | `us-east-1` | Région de déploiement |
| `environment` | `dev` | Nom de l'environnement |
| `project_name` | `heartcare` | Préfixe de nommage |
| `vpc_cidr` | `10.20.0.0/16` | Bloc réseau principal |
| `instance_type` | `t3.micro` | Type d'instance EC2 |
| `min_size` / `max_size` | `2` / `4` | Bornes de l'Auto Scaling Group |
| `desired_capacity` | `2` | Instances souhaitées |
| `db_instance_class` | `db.t3.micro` | Classe RDS |
| `db_password` | — | **Via `TF_VAR_db_password`**, jamais versionné |
| `multi_az` | `false` | Multi-AZ RDS (`true` en prod) |
| `create_iam_role` | `false` | `true` sur un compte AWS standard |
| `enable_iam_tags` | `false` | `true` sur un compte AWS standard |

Chaque environnement porte son `terraform.tfvars`, **versionné**. C'est
délibéré : ce fichier ne contient aucun secret, et en faire la source de vérité
unique garantit que le pipeline et le poste de développement planifient sur les
mêmes entrées. Quand il ne l'était pas, la CI retombait sur les valeurs par
défaut des variables, divergeait du local sur un simple tag, et recalculait une
modification sur toutes les ressources — ce qui faisait échouer l'`apply`.

Le mot de passe de la base n'y figure pas. Il vient de `TF_VAR_db_password` en
local, et du secret GitHub `TF_VAR_DB_PASSWORD` dans le pipeline.
`terraform.tfvars.example` reste fourni comme modèle commenté.

### Sorties principales

| Sortie | Contenu |
|---|---|
| `alb_url` | URL publique de l'application |
| `alb_dns_name` | Nom DNS de l'ALB |
| `vpc_id` | Identifiant du VPC |
| `autoscaling_group_name` | Nom de l'Auto Scaling Group |
| `db_instance_endpoint` | Point de connexion RDS (privé) |
| `s3_bucket_id` | Bucket applicatif |
| `iam_app_policy_arn` | Politique de moindre privilège |
| `iam_app_instance_profile_name` | Instance profile des instances |

---

## 7. Pipeline CI/CD

Défini dans [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml).

### Job `terraform-ci` — à chaque push et à chaque Pull Request

Exécuté **en matrice sur les trois environnements** `dev`, `test` et `prod` :

1. Récupération du dépôt
2. Installation de Terraform
3. Authentification AWS depuis les secrets GitHub
4. `terraform fmt -check -recursive`
5. `terraform init`
6. `terraform validate`
7. `terraform plan -refresh=false -out=tfplan`
8. `terraform show -no-color tfplan > plan.txt`, publié en artefact (30 jours)

Ce job ne modifie jamais l'infrastructure. Une Pull Request produit donc trois
plans consultables, sans rien appliquer.

### Job `apply-dev` — automatique

Ne s'exécute que sur un **push vers `main`**, jamais sur une Pull Request, et
dépend de la réussite du job précédent.

### Job `apply-manuel` — `test` et `prod`

Ne s'exécute **que sur déclenchement manuel** (*Actions → Run workflow*), avec
l'environnement choisi dans la liste, et uniquement depuis `main`. Aucun push
ne peut déclencher un déploiement `test` ou `prod` : c'est garanti par le
workflow lui-même, indépendamment de toute configuration.

### Branche de déclenchement

Les deux jobs d'`apply` ne se déclenchent que depuis la **branche par défaut du
dépôt**, résolue dynamiquement :

```yaml
github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
```

Elle n'est pas codée en dur. Le dépôt utilise `master` ; la condition suit
automatiquement si elle change.

### Configuration GitHub

#### a. Les secrets — *Settings → Secrets and variables → Actions*

| Secret | Contenu |
|---|---|
| `AWS_ACCESS_KEY_ID` | Clé d'accès |
| `AWS_SECRET_ACCESS_KEY` | Clé secrète |
| `AWS_SESSION_TOKEN` | Jeton de session |
| `TF_VAR_DB_PASSWORD` | Mot de passe RDS |

> Sur AWS Academy, ces identifiants **expirent à chaque session**. Il faut les
> recopier depuis le bouton *AWS Details* du Learner Lab à chaque reprise, sans
> quoi l'étape d'authentification du pipeline échoue.

#### b. Les environnements — *Settings → Environments*

Trois environnements sont déclarés :

| Environnement | Relecteur obligatoire | Branches autorisées |
|---|---|---|
| `dev` | non | toutes |
| `test` | **oui** | `master` |
| `prod` | **oui** | `master` |

L'approbation obligatoire sur `test` et `prod` est ce qui matérialise la
validation manuelle exigée au point 19.1.9 du cahier des charges : le job
d'`apply` reste en attente jusqu'à ce qu'un relecteur l'approuve dans l'onglet
*Actions*.

> Si ces environnements sont absents, GitHub les crée à la volée au premier
> usage, **sans aucune protection** : le déploiement reste manuel, mais
> personne n'a à l'approuver. L'extension GitHub Actions de VS Code signale
> alors `Value 'dev' is not valid` sur la ligne `environment:`.

---

## 8. Coûts

Environ **0,18 $ par heure**, soit 127 $ par mois en fonctionnement continu.

| Poste | Part |
|---|---:|
| NAT Gateways (×2) | 52 % |
| Load Balancer | 13 % |
| Adresses IPv4 publiques | 11 % |
| Instances EC2 (×2) | 12 % |
| RDS + stockage | 12 % |

Le crédit de 50 $ d'AWS Academy couvre environ **285 heures**, soit une
douzaine de jours en continu. Détail et leviers de réduction dans
**[docs/couts.md](docs/couts.md)**.

> Le levier qui compte : `terraform destroy` entre deux sessions de travail.

---

## 9. Limites connues

### Restrictions AWS Academy Learner Lab

Trois SCP d'organisation s'appliquent au compte et ne peuvent pas être levées.
Chacune est contournée par une variable, de sorte que le code reste applicable
tel quel sur un compte AWS standard.

| Action refusée | Conséquence | Contournement |
|---|---|---|
| `iam:CreateRole`, `iam:AttachRolePolicy` | La politique de moindre privilège est créée mais non rattachée ; les instances portent `LabRole` | `create_iam_role = false` ; passer à `true` ailleurs |
| `iam:TagPolicy`, `iam:TagInstanceProfile` | Les ressources IAM ne peuvent pas être taguées | Provider aliasé `aws.untagged` ; `enable_iam_tags = false` |
| `s3:GetBucketObjectLockConfiguration` | Toute relecture d'un `aws_s3_bucket` échoue | `-refresh=false` ; buckets du backend créés par `scripts/bootstrap.sh` |
| `autoscaling:StartInstanceRefresh` | Pas de rolling update géré par l'ASG | Terminer les instances une à une |

Le backend S3 distant, lui, **fonctionne normalement** : il n'utilise que
`GetObject`, `PutObject` et `ListObjects`, qu'aucune SCP ne bloque.

### Choix assumés, à revoir en production

- L'ALB n'écoute qu'en **HTTP** ; HTTPS demande un certificat ACM et un domaine.
- Le Security Group bastion ouvre le **port 22 à `0.0.0.0/0`** ; à restreindre.
- RDS a `deletion_protection = false` et `skip_final_snapshot = true`, pour
  permettre la destruction complète demandée par le cahier des charges.

Justifications complètes dans **[docs/securite.md](docs/securite.md)**.

---

## 10. Dépannage

| Symptôme | Cause probable | Correction |
|---|---|---|
| `ExpiredToken` / `InvalidClientTokenId` | Session AWS Academy expirée | Recopier les identifiants du Learner Lab dans `~/.aws/credentials` |
| `Error acquiring the state lock` | Exécution interrompue | `terraform force-unlock <ID>` après avoir vérifié qu'aucune autre n'est en cours |
| `GetObjectLockConfiguration ... AccessDenied` | SCP AWS Academy | Ajouter `-refresh=false` au `plan` et à l'`apply` |
| `iam:CreateRole ... AccessDenied` | SCP AWS Academy | Laisser `create_iam_role = false` |
| Cibles `unhealthy` dans le Target Group | `user_data` encore en cours | Attendre 5 min ; la période de grâce est de 300 s |
| `502 Bad Gateway` | gunicorn arrêté | `systemctl status heartcare` sur l'instance |
| `terraform fmt -check` échoue en CI | Fichiers non formatés | `terraform fmt -recursive .` puis commit |
| Plan non vide juste après un apply | Dérive ou valeur instable | Vérifier qu'aucun tag n'utilise `timestamp()` |

### Ouvrir une session sur une instance

Les instances n'ont pas d'adresse publique. Session Manager permet d'y accéder
sans ouvrir de port :

```bash
aws ssm start-session --target <instance-id>
```

Ou exécuter une commande ponctuelle :

```bash
aws ssm send-command --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -50 /var/log/user-data.log"]'
```

### Journaux utiles

| Fichier | Contenu |
|---|---|
| `/var/log/user-data.log` | Déroulé complet du script de démarrage |
| `systemctl status heartcare` | État de gunicorn |
| `journalctl -u nginx` | Journal de nginx |

---

## 11. Tests

Les neuf tests obligatoires, leur procédure et leurs résultats constatés sont
consignés dans **[docs/tests.md](docs/tests.md)**.

---

## 12. L'application Heart Care

Application Django de gestion de cabinet médical : gestion des médecins, des
services, de la galerie et prise de rendez-vous. La documentation d'origine du
projet applicatif est conservée dans
**[docs/application-heart-care.md](docs/application-heart-care.md)**.

Sur chaque instance, le `user_data` clone le dépôt, installe les dépendances
dans un environnement virtuel, exécute `collectstatic` et `migrate`, puis lance
gunicorn derrière nginx. L'endpoint `/whoami` indique quelle instance a servi
la requête, ce qui permet d'observer la répartition de charge.

---

## Licence

Voir [LICENSE](LICENSE).
