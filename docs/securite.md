# Choix de sécurité

Ce document justifie les décisions de sécurité prises sur l'infrastructure
Heart Care, et signale honnêtement les points qui restent ouverts.

## 1. Segmentation réseau

L'infrastructure est découpée en trois étages, du plus exposé au plus protégé.

| Étage | Sous-réseaux | Exposition | Contenu |
|---|---|---|---|
| Public | `10.20.1.0/24`, `10.20.2.0/24` | Internet entrant | ALB uniquement |
| Applicatif privé | `10.20.11.0/24`, `10.20.12.0/24` | Sortant via NAT | Instances EC2 |
| Base de données privé | `10.20.21.0/24`, `10.20.22.0/24` | Aucune | RDS PostgreSQL |

Les instances applicatives n'ont **pas d'adresse IP publique**. Elles joignent
Internet par les NAT Gateways pour installer leurs paquets, mais rien ne peut
les joindre directement depuis l'extérieur.

Les sous-réseaux de base de données ont leur **propre table de routage, sans
route par défaut vers Internet**. C'est une seconde barrière, indépendante des
Security Groups : même une règle de pare-feu mal écrite ne rendrait pas la base
joignable depuis l'extérieur, faute de chemin réseau.

## 2. Security Groups en chaîne

Les règles entrantes désignent des **Security Groups sources**, jamais des
plages CIDR :

```
Internet  --80/443-->  SG ALB  --8000-->  SG App  --5432-->  SG RDS
```

| Security Group | Entrant autorisé | Source |
|---|---|---|
| `sg-alb` | 80, 443 | `0.0.0.0/0` |
| `sg-app` | 8000 | `sg-alb` |
| `sg-app` | 22 | `sg-bastion` |
| `sg-rds` | 5432 | `sg-app` |

L'intérêt : une instance ne peut joindre la base **que parce qu'elle porte le
Security Group applicatif**, pas parce qu'elle se trouve dans un certain
sous-réseau. La règle reste juste si le plan d'adressage change, et une
instance ajoutée par erreur hors du groupe n'a aucun accès.

## 3. Gestion des secrets

Aucun secret n'est présent dans le dépôt Git. La chaîne complète :

| Emplacement | Contenu | Protection |
|---|---|---|
| GitHub Actions Secrets | identifiants AWS, `TF_VAR_DB_PASSWORD` | coffre chiffré, valeurs masquées dans les journaux |
| Variable Terraform `db_password` | mot de passe RDS | marquée `sensitive`, jamais affichée |
| SSM Parameter Store | mot de passe, chaîne de connexion | type `SecureString`, chiffré par KMS |
| `.gitignore` | `*.tfvars`, `*.tfstate`, `.terraform/` | empêche tout versionnement accidentel |

`terraform.tfvars.example` est fourni sans aucune valeur sensible ; le fichier
`terraform.tfvars` réel n'est jamais versionné.

Le paramètre SSM créé par le module `security` utilise
`lifecycle { ignore_changes = [value] }` : Terraform crée l'emplacement, la
valeur réelle y est injectée hors du code.

## 4. Chiffrement

| Donnée | Chiffrement |
|---|---|
| État Terraform (S3) | AES256 côté serveur, `encrypt = true` dans le backend |
| Base RDS | `storage_encrypted = true` |
| Buckets S3 applicatifs | AES256 par défaut |
| Paramètres SSM sensibles | `SecureString`, KMS |
| Trafic vers S3 | la politique de bucket refuse `aws:SecureTransport = false` |

## 5. Accès public bloqué sur S3

Les quatre verrous sont actifs sur tous les buckets du projet, sans exception :
`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`,
`RestrictPublicBuckets`. Le cahier des charges autorise une exception si elle
est documentée — le projet n'en utilise aucune.

## 6. Moindre privilège IAM

La politique applicative (module `iam`) n'accorde que ce dont l'application a
besoin, chaque droit étant borné à ses propres ressources :

- S3 limité au bucket du projet et à son bucket de journaux ;
- SSM limité à l'arborescence `/<projet>/<environnement>/*` ;
- `kms:Decrypt` borné par la condition `kms:ViaService = ssm` ;
- CloudWatch Logs limité aux groupes `/aws/ec2/<projet>-<env>*` ;
- Session Manager, pour administrer une instance **sans ouvrir de port SSH**.

Aucune déclaration n'utilise `Action: "*"`.

## 7. État Terraform protégé

Le backend S3 satisfait les exigences de la section 16.1 du cahier des charges :

| Exigence | Mise en œuvre |
|---|---|
| Stockage distant | `s3://heartcare-terraform-state-<compte>/` |
| Chiffrement | `encrypt = true`, AES256 sur le bucket |
| Versioning | activé — un état corrompu peut être restauré |
| Verrouillage | `use_lockfile = true`, verrou natif S3 |
| Séparation des environnements | une clé par environnement : `dev/`, `test/`, `prod/` |
| Accès restreint | bucket privé, accès public bloqué, journaux d'accès |

## 8. Pipeline CI/CD

- `apply` n'est jamais déclenché par une Pull Request.
- `dev` ne s'applique que sur un push vers `main`.
- `test` et `prod` ne s'appliquent **que sur déclenchement manuel**
  (`workflow_dispatch`), depuis `main`. Aucun push ne peut les déployer : la
  garantie vient du workflow lui-même, pas d'un réglage.
- Les identifiants proviennent du coffre GitHub, jamais du dépôt.
- GitHub masque automatiquement les valeurs de secrets dans les journaux.

- l'approbation par un relecteur est **effective** sur `test` et `prod` : les
  environnements GitHub correspondants portent la protection
  `required_reviewers`, et leur politique de branche limite les déploiements à
  `master`. Le job d'`apply` reste en attente tant qu'un relecteur ne l'a pas
  approuvé (exigence 19.1, point 9).
- les jobs d'`apply` ne se déclenchent que depuis la branche par défaut du
  dépôt, résolue dynamiquement plutôt que codée en dur.

## 9. Points ouverts, assumés

Trois éléments ne sont pas au niveau d'une production réelle. Ils sont listés
ici plutôt que passés sous silence.

**Le Security Group bastion ouvre le port 22 depuis `0.0.0.0/0`.** C'est trop
large. Dans un déploiement réel il faut le restreindre à l'adresse IP de
l'administrateur. Le besoin est d'ailleurs discutable : la politique IAM
accorde déjà Session Manager, qui permet d'ouvrir une session sur une instance
sans aucun port ouvert. Le bastion pourrait être supprimé.

**L'ALB n'écoute qu'en HTTP.** Le trafic entre le navigateur et l'ALB n'est pas
chiffré. Activer HTTPS demande un certificat ACM et un nom de domaine, hors
périmètre du lab. Le Security Group de l'ALB autorise déjà le port 443 pour
que l'ajout d'un listener soit la seule modification nécessaire.

**`deletion_protection = false` et `skip_final_snapshot = true` sur RDS.** Ces
réglages sont volontaires : l'environnement doit pouvoir être détruit
intégralement à la fin de la démonstration, comme le demande la section 5 du
cahier des charges. **Ils doivent être inversés pour un environnement de
production.**

## 10. Restrictions de l'environnement AWS Academy

Trois restrictions imposées par des SCP d'organisation ont façonné des choix
techniques. Elles sont hors de portée du compte et ne peuvent pas être levées.

### `iam:CreateRole` et `iam:AttachRolePolicy` refusés

La politique de moindre privilège est bien créée, mais ne peut pas être
rattachée à un rôle. Les instances portent donc `LabRole`, dont les permissions
sont larges. Le code du rôle et de son attachement est écrit et piloté par
`create_iam_role` : sur un compte AWS standard, passer cette variable à `true`
applique réellement le moindre privilège, sans autre modification.

### `iam:TagPolicy` et `iam:TagInstanceProfile` refusés

Les ressources IAM ne peuvent pas porter de tags. Comme le provider principal
injecte `default_tags` dans toutes les ressources, leur création échouait. Le
module `iam` utilise donc un provider aliasé `aws.untagged`, et le tagging est
piloté par `enable_iam_tags`.

### `s3:GetBucketObjectLockConfiguration` refusé

Le provider AWS appelle cette API à chaque lecture d'une ressource
`aws_s3_bucket`. Conséquences et contournements :

- **Le backend S3 n'est pas affecté** : il n'utilise que `GetObject`,
  `PutObject` et `ListObjects`. Le backend distant fonctionne normalement.
- Les `plan` et `apply` du projet utilisent `-refresh=false`, ce qui évite la
  lecture bloquée. Le code a par ailleurs été corrigé pour que le plan soit
  stable : le tag `CreatedAt` utilisait `timestamp()`, qui changeait à chaque
  exécution et forçait une mise à jour inutile de chaque bucket.
- Les buckets du backend ne peuvent pas être gérés par Terraform du tout
  (`create`, `import` et `refresh` échouent sur cette lecture). Ils sont créés
  par `terraform/scripts/bootstrap.sh`. La configuration Terraform équivalente
  reste fournie dans `terraform/bootstrap/` comme référence pour un compte
  standard.

Le compromis à retenir : `-refresh=false` signifie que Terraform ne détecte pas
une dérive introduite à la main dans la console AWS. Sur un compte sans cette
SCP, il faut retirer ce drapeau.
