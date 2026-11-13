# Rapport de projet — Infrastructure Cloud Heart Care

**Terraform et CI/CD — Parcours Cloud et Réseaux**

| | |
|---|---|
| Application déployée | Heart Care, gestion de cabinet médical (Django) |
| Fournisseur Cloud | AWS, région `us-east-1` |
| Outil d'infrastructure | Terraform ≥ 1.6, provider AWS ~> 5.0 |
| Pipeline | GitHub Actions |
| Dépôt | https://github.com/badretr/Heart-Care |

---

## 1. Contexte et objectifs

Le projet consiste à héberger une application Web dans le Cloud en respectant
trois contraintes : l'application doit rester disponible si une instance tombe,
les instances et la base de données ne doivent jamais être joignables depuis
Internet, et l'ensemble de l'infrastructure doit être décrit en code, donc
reproductible à l'identique dans trois environnements.

L'application retenue est **Heart Care**, un projet Django existant de gestion
de cabinet médical. Ce choix est délibéré : déployer une application réelle,
avec ses fichiers statiques, ses migrations et ses défauts, fait apparaître des
problèmes qu'une page de test statique n'aurait jamais révélés. La section 7 y
revient.

Le budget est contraint : 50 $ de crédit AWS Academy, soit environ douze jours
de fonctionnement continu de l'infrastructure complète.

---

## 2. Architecture retenue

### 2.1 Principe

L'infrastructure est découpée en trois étages, du plus exposé au plus protégé.

| Étage | Sous-réseaux | Exposition | Contenu |
|---|---|---|---|
| Public | `10.20.1.0/24`, `10.20.2.0/24` | Internet entrant | ALB, NAT Gateways |
| Applicatif privé | `10.20.11.0/24`, `10.20.12.0/24` | Sortant via NAT | Instances EC2 |
| Base de données privé | `10.20.21.0/24`, `10.20.22.0/24` | Aucune | RDS PostgreSQL |

Chaque étage est dupliqué sur deux zones de disponibilité, `us-east-1a` et
`us-east-1b`. Le schéma complet figure dans [architecture.md](architecture.md).

### 2.2 Composants

| Composant | Choix | Justification |
|---|---|---|
| Load Balancer | ALB, HTTP :80 | Seul point d'entrée public |
| Calcul | Auto Scaling Group, 2 à 4 `t3.micro` | Répartition sur deux zones, remplacement automatique |
| Base | RDS PostgreSQL 15, `db.t3.micro` | Service managé, sauvegardes automatiques |
| Stockage | 2 buckets S3 (applicatif, journaux) | Versioning, chiffrement, cycle de vie |
| Secrets | SSM Parameter Store, `SecureString` | Aucun secret dans le dépôt |
| État Terraform | S3 chiffré, versionné, verrou natif | Travail collaboratif possible |

### 2.3 Le chemin d'une requête

Suivre une requête de bout en bout montre où chaque garde-fou intervient.

| Étape | Composant | Contrôle appliqué |
|---|---|---|
| 1 | Navigateur | requête HTTP vers le nom DNS de l'ALB |
| 2 | ALB | `sg-alb` accepte 80 et 443 depuis Internet |
| 3 | ALB | choisit une cible **saine** du Target Group |
| 4 | nginx :8000 | `sg-app` n'accepte 8000 que depuis `sg-alb` |
| 5 | nginx | sert `/static/` depuis le disque, répond `/health/` et `/whoami` |
| 6 | gunicorn :8001 | Django traite la requête applicative |
| 7 | RDS :5432 | `sg-rds` n'accepte 5432 que depuis `sg-app` |

Le détail du port compte : nginx et gunicorn écoutaient tous deux sur 8000
dans une première version, et gunicorn ne démarrait pas. L'ALB renvoyait un
`502 Bad Gateway` sans que rien n'indique la cause côté infrastructure — le
Target Group était simplement vide de cibles saines.

### 2.4 Ce qui se passe quand une instance tombe

| Instant | Événement |
|---|---|
| T+0 | L'instance s'arrête |
| T+30 s | Premier health check en échec |
| T+60 s | Deuxième échec : l'ALB retire la cible du Target Group |
| T+60 s | L'Auto Scaling Group constate l'écart avec la capacité souhaitée |
| T+2 min | Une nouvelle instance démarre, le `user_data` s'exécute |
| T+5 min | La nouvelle instance passe `healthy` et reçoit du trafic |

Pendant toute cette fenêtre, l'instance restante sert l'intégralité du trafic.
C'est ce que le test de panne a mesuré : trente requêtes, trente réponses 200.

### 2.5 Deux décisions structurantes

**Une NAT Gateway par zone, pas une seule.** Une NAT unique coûterait 33 $ de
moins par mois, mais ferait de sa zone un point de défaillance unique pour tout
le trafic sortant. L'économie ne justifiait pas de dégrader précisément la
propriété que le projet doit démontrer. C'est néanmoins le poste de coût
dominant, à 52 % de la facture.

**Les sous-réseaux de base de données n'ont aucune route par défaut.** La base
n'a aucun besoin de sortir sur Internet. Lui retirer le chemin réseau est une
barrière indépendante des Security Groups : même une règle de pare-feu erronée
ne la rendrait pas joignable.

---

## 3. Organisation du code

### 3.1 Sept modules

```
terraform/modules/
├── network/        VPC, subnets, IGW, NAT, routage
├── security/       Security Groups, paramètre SSM
├── iam/            politique de moindre privilège, instance profile
├── load-balancer/  ALB, listener, target group
├── compute/        Launch Template, user_data, ASG, politiques
├── database/       RDS, subnet group, parameter group
└── storage/        S3, versioning, chiffrement, cycle de vie
```

Chaque module contient `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
et un `README.md` documentant ses entrées, ses sorties et un exemple d'appel.

Le module `iam` ne figurait pas dans le découpage proposé par le cahier des
charges, qui rattachait les rôles IAM au module `security`. Il a été séparé
pour une raison technique : ses ressources ont besoin d'un provider AWS
distinct, sans `default_tags` (voir section 6.2). Les mélanger au module
`security` aurait imposé ce provider à tous les Security Groups.

### 3.2 Trois environnements

```
terraform/environments/
├── dev/    2 × t3.micro, db.t3.micro, mono-AZ
├── test/   proche de prod, réduit
└── prod/   capacité supérieure, multi_az = true
```

Les modules sont communs, les différences passent exclusivement par variables.
Chaque environnement possède son propre état, sous une clé distincte du bucket :
une erreur sur `dev` ne peut pas corrompre `prod`.

### 3.3 Comment les trois environnements diffèrent

Les modules sont strictement communs. Toute la différence passe par variables,
ce qui garantit qu'un correctif appliqué à un module profite aux trois.

| Paramètre | `dev` | `test` | `prod` |
|---|---|---|---|
| `instance_type` | `t3.micro` | `t3.small` | `t3.medium` |
| `desired_capacity` | 2 | 3 | 4 |
| `max_size` | 3 | 4 | 8 |
| `db_instance_class` | `db.t3.micro` | `db.t3.small` | `db.t3.medium` |
| `db_allocated_storage` | 20 Go | 30 Go | 50 Go |
| `backup_retention_days` | 7 | 14 | 30 |
| `multi_az` | `false` | `false` | **`true`** |
| Déploiement | automatique sur push | manuel + approbation | manuel + approbation |

`multi_az` est la différence la plus coûteuse : elle double le prix de
l'instance RDS, une instance de secours étant maintenue dans une seconde zone.
Justifiée en production, inutile en développement.

Chaque environnement possède son propre fichier d'état, sous une clé distincte
du même bucket :

```
s3://heartcare-terraform-state-<compte>/
├── dev/terraform.tfstate
├── test/terraform.tfstate
└── prod/terraform.tfstate
```

Une erreur sur `dev` ne peut pas corrompre `prod` : ce sont deux objets
distincts, chacun verrouillé séparément pendant une opération.

### 3.4 Un choix revu : versionner les `terraform.tfvars`

Les fichiers de variables d'environnement étaient initialement exclus du dépôt,
par prudence. C'était une erreur de conception, révélée par le pipeline : sans
eux, la CI retombait sur les valeurs par défaut des variables et travaillait
donc sur des entrées différentes de celles du poste de développement.

Ils sont désormais versionnés, **sans aucun secret** — le mot de passe de la
base reste fourni par `TF_VAR_db_password`. Le cahier des charges le formule
d'ailleurs ainsi : « aucune valeur sensible en clair dans `terraform.tfvars` »,
ce qui suppose bien que le fichier existe et soit partagé.

### 3.5 Qualité du code

- `required_version` et `required_providers` déclarés dans chaque module.
- Variables typées, documentées, et validées là où la valeur est critique
  (`min_size`, `max_size` et `desired_capacity` sont bornés entre 1 et 10).
- `locals` pour les noms et les tags communs.
- `count` sur les listes de zones, ce qui permet de passer à trois zones sans
  toucher au code.
- Tags obligatoires sur toutes les ressources : `Project`, `Environment`,
  `Owner`, `ManagedBy`.
- `terraform fmt -check -recursive` passe sans différence.

---

## 4. Sécurité

### 4.1 Security Groups en chaîne

```
Internet --80/443--> sg-alb --8000--> sg-app --5432--> sg-rds
```

Chaque règle entrante désigne un **Security Group source**, jamais une plage
d'adresses. Une instance ne peut joindre la base que parce qu'elle porte le
Security Group applicatif, pas parce qu'elle se trouve dans un certain
sous-réseau : la règle reste juste si le plan d'adressage change.

### 4.2 Secrets

Aucun secret n'est présent dans le dépôt. Le mot de passe de la base transite
par `TF_VAR_db_password`, alimenté depuis le coffre GitHub Actions, est marqué
`sensitive` dans Terraform, et finit dans SSM Parameter Store en `SecureString`.
Le `.gitignore` exclut `*.tfvars`, `*.tfstate` et `.terraform/` ; seul
`terraform.tfvars.example`, sans valeur sensible, est versionné.

### 4.3 Chiffrement

L'état Terraform, la base RDS, les buckets S3 et les paramètres SSM sensibles
sont tous chiffrés au repos. La politique des buckets refuse en outre les
requêtes non chiffrées en transit.

### 4.4 Moindre privilège IAM

La politique applicative n'accorde que ce dont l'application a besoin, chaque
droit étant borné à ses propres ressources : S3 limité au bucket du projet, SSM
limité à l'arborescence `/<projet>/<environnement>/*`, `kms:Decrypt` borné par
la condition `kms:ViaService = ssm`, CloudWatch Logs limité aux groupes du
projet. Aucune déclaration n'utilise `Action: "*"`.

La politique accorde également l'accès Session Manager, ce qui permet d'ouvrir
une session sur une instance **sans ouvrir le moindre port SSH**. Cette
capacité s'est révélée décisive au diagnostic (section 7.3).

### 4.5 Chiffrement, partout où la donnée se pose

| Donnée | Au repos | En transit |
|---|---|---|
| État Terraform | AES256 sur S3, `encrypt = true` | HTTPS vers l'API S3 |
| Base RDS | `storage_encrypted = true` | dans le VPC uniquement |
| Buckets applicatifs | AES256 | politique refusant `aws:SecureTransport = false` |
| Paramètres SSM sensibles | `SecureString`, KMS | HTTPS vers l'API SSM |
| Navigateur → ALB | — | **non chiffré** tant qu'aucun certificat n'est fourni |

La dernière ligne est la seule faiblesse, et elle est explicitée plutôt que
noyée. Le listener HTTPS est codé dans le module `load-balancer` et s'active
dès que `certificate_arn` est renseigné ; il reste vide parce qu'un certificat
suppose un nom de domaine, et que le nom DNS d'un ALB appartient à
`amazonaws.com`, qu'ACM ne peut pas valider.

### 4.6 Ce qui protège réellement la base de données

Trois barrières indépendantes, et c'est volontaire : chacune suffirait, mais
aucune ne dépend des deux autres.

| Barrière | Nature | Ce qu'elle arrête |
|---|---|---|
| `publicly_accessible = false` | configuration RDS | l'attribution d'une adresse publique |
| Aucune route par défaut sur les sous-réseaux DB | routage | tout chemin réseau depuis l'extérieur |
| `sg-rds` n'accepte que `sg-app` | pare-feu | toute source autre que les instances applicatives |

Le test l'a vérifié : l'endpoint RDS résout vers `10.20.21.169`, une adresse
privée, et la connexion depuis Internet est refusée.

### 4.7 Points ouverts, assumés

Trois éléments ne sont pas au niveau d'une production réelle, et sont signalés
plutôt que passés sous silence : l'ALB n'écoute qu'en HTTP, le Security Group
bastion ouvre le port 22 à `0.0.0.0/0`, et RDS a `deletion_protection = false`.
Ce dernier point est volontaire : le cahier des charges impose que
l'environnement puisse être détruit intégralement après la démonstration.

Justifications complètes dans [securite.md](securite.md).

---

## 5. Pipeline CI/CD

Le workflow GitHub Actions se déclenche à chaque push et à chaque Pull Request.

**Job `terraform-ci`**, à chaque exécution : récupération du dépôt, installation
de Terraform, authentification AWS depuis les secrets, puis `fmt -check`,
`init`, `validate`, `plan`, et publication du plan lisible en artefact.

Les neuf étapes exigées par la section 19.1 du cahier des charges y figurent
toutes :

| # | Étape | Mise en œuvre |
|---|---|---|
| 1 | Récupérer le dépôt | `actions/checkout` |
| 2 | Installer Terraform | `hashicorp/setup-terraform`, version alignée sur le poste local |
| 3 | Authentification sécurisée | `aws-actions/configure-aws-credentials` depuis les secrets |
| 4 | `terraform fmt -check` | sur l'ensemble du dépôt, récursif |
| 5 | `terraform init` | backend S3 distant |
| 6 | `terraform validate` | — |
| 7 | `terraform plan` | avec `-out=tfplan` |
| 8 | Conserver le plan | `terraform show` puis artefact conservé 30 jours |
| 9 | Validation manuelle test/prod | `workflow_dispatch` + relecteur obligatoire |

Le job de verification tourne **en matrice sur les trois environnements**, ce
qui garantit que `test` et `prod` restent valides même s'ils ne sont pas
déployés.

**Application**, sous conditions : `dev` s'applique sur un push vers `main` ;
`test` et `prod` ne s'appliquent que sur déclenchement manuel
(`workflow_dispatch`), depuis `main`. Aucun push ne peut déployer `prod`.

Une Pull Request produit donc trois plans consultables sans jamais rien
appliquer, ce qui est le comportement demandé.

**L'approbation est effective.** Les environnements GitHub `test` et `prod`
portent la protection `required_reviewers` et limitent les déploiements à la
branche `master` : le job d'`apply` reste en attente tant qu'un relecteur ne
l'a pas approuvé.

Deux défauts ont été corrigés au passage. Le workflow testait
`refs/heads/main`, alors que le travail se fait sur `master` : les deux jobs
d'`apply` étaient **systématiquement ignorés**, sans que rien ne le signale —
un pipeline vert qui n'applique jamais rien. La condition compare désormais à
la branche par défaut du dépôt, résolue dynamiquement. Et le dépôt portait deux
branches divergentes dès la racine, `main` ne contenant qu'un commit initial ;
`master` est devenue la branche par défaut.

---

## 6. Contraintes de l'environnement AWS Academy

Le compte est soumis à des SCP d'organisation qui refusent certaines actions,
hors de portée du compte. Chaque restriction a été identifiée par test direct,
puis contournée par une variable, de sorte que **le code reste applicable tel
quel sur un compte AWS standard**.

### 6.1 Les permissions IAM, testées une par une

| Action | État |
|---|---|
| `iam:CreatePolicy` | autorisée |
| `iam:CreateInstanceProfile` | autorisée |
| `iam:AddRoleToInstanceProfile` | autorisée |
| `iam:CreateRole` | **refusée** |
| `iam:AttachRolePolicy` | **refusée** |
| `iam:TagPolicy`, `iam:TagInstanceProfile` | **refusées** |

Le blocage n'est donc pas « IAM dans son ensemble », comme on pouvait le croire
avant de tester : seules la création de rôle et l'attachement de politique le
sont. La politique de moindre privilège est réellement créée et déployée ; elle
ne peut simplement pas être rattachée. La sortie `policy_attached_to_role` le
signale explicitement plutôt que de laisser croire que le moindre privilège
s'applique. Sur un compte standard, `create_iam_role = true` suffit.

### 6.2 Le piège des `default_tags`

La création de l'instance profile échouait sur `iam:TagInstanceProfile`, alors
que le code ne demandait aucun tag. La cause : le bloc `default_tags` du
provider, recommandé par le cahier des charges lui-même, injecte les tags
communs dans **toutes** les ressources, y compris IAM.

Le module `iam` utilise donc un provider aliasé `aws.untagged`, sans
`default_tags`, et le tagging y est piloté explicitement par `enable_iam_tags`.

### 6.3 Le backend distant : une conclusion initiale erronée

Une SCP refuse `s3:GetBucketObjectLockConfiguration`. Le provider AWS appelle
cette API à chaque lecture d'une ressource `aws_s3_bucket` — à la création, au
`refresh` et à l'`import`. Toute tentative de gérer un bucket par Terraform
échouait.

Nous en avions d'abord conclu que **le backend S3 était impossible**, et basculé
sur un backend local, ce qui contredisait frontalement l'exigence 16 du cahier
des charges.

Cette conclusion était fausse. Le backend S3 n'appelle jamais cette API : il
n'utilise que `GetObject`, `PutObject` et `ListObjects`. Un test direct l'a
confirmé, et les trois environnements ont été migrés vers un backend S3 chiffré,
versionné et verrouillé.

La leçon vaut d'être retenue : une erreur `AccessDenied` sur une API S3 avait
été généralisée à « S3 est bloqué », sans vérifier quelles API chaque
fonctionnalité utilise réellement. Le test coûtait cinq minutes.

Seuls les buckets du backend restent hors Terraform, créés par
`scripts/bootstrap.sh`. La configuration Terraform équivalente est conservée
dans `terraform/bootstrap/` comme référence pour un compte standard.

### 6.4 Le bucket qui naît « tainted »

Le déploiement de l'environnement `test`, le premier créé depuis zéro après
`dev`, a révélé un dernier visage de la même SCP.

`ignore_changes` règle le cas des mises à jour. Il ne règle pas celui de la
**création** : Terraform relit toute ressource qu'il vient de créer, pour en
enregistrer les attributs. Cette lecture échoue, et Terraform marque alors le
bucket `tainted`. Au plan suivant, il veut le **remplacer** — le détruire puis
le recréer — ce qui échouerait exactement de la même façon. L'environnement
serait indéployable.

Le bucket existe pourtant dans AWS, correctement configuré. Seule la trace
manque dans l'état. Deux commandes suffisent :

```bash
terraform untaint module.storage.aws_s3_bucket.main
terraform untaint module.storage.aws_s3_bucket.logs
terraform apply -refresh=false
```

Le second `apply` crée les onze sous-ressources restantes, et le plan redevient
stable. L'étape ne se reproduit pas : elle n'est nécessaire qu'au tout premier
déploiement d'un environnement.

C'est la troisième fois que la même SCP se manifeste sous une forme différente
— au `refresh`, à la mise à jour, puis à la création. Chaque fois, le symptôme
désignait une cause différente de la vraie.

### 6.5 Un diff perpétuel qui bloquait S3

Chaque `apply` tentait de modifier les deux buckets applicatifs, ce qui
déclenchait la lecture interdite et faisait échouer l'opération. La cause était
dans notre propre code : le tag `CreatedAt` utilisait `timestamp()`, qui renvoie
une valeur différente à chaque exécution. Terraform voyait donc une modification
sur **toutes** les ressources, à chaque fois.

Le tag provient désormais d'une variable à valeur fixe. Le plan est stable, et
les sous-ressources S3 qui n'avaient jamais pu être créées — versioning,
chiffrement, cycle de vie, blocage public, journalisation — le sont.

Une SCP masquait un défaut de conception bien à nous.

---

## 7. Déployer une application réelle

### 7.1 Le choix

Le cahier des charges se satisfait d'un `user_data` installant nginx et
affichant le nom d'hôte. Nous avons déployé l'application Heart Care complète :
clonage du dépôt, environnement virtuel Python, `collectstatic`, `migrate`,
gunicorn derrière nginx, service systemd avec redémarrage automatique.

L'exigence d'observer la répartition de charge est satisfaite par un endpoint
`/whoami` servi par nginx et un en-tête `X-Served-By`, qui indiquent l'instance
ayant traité la requête sans modifier les pages de l'application.

### 7.2 Un conflit de ports

nginx et gunicorn écoutaient tous deux sur le port 8000. gunicorn ne démarrait
pas, et l'ALB renvoyait `502 Bad Gateway`. nginx écoute désormais sur 8000 et
transmet à gunicorn sur `127.0.0.1:8001`.

### 7.3 Un défaut masqué par `DEBUG = True`

En vérifiant le site, nous avons constaté que Django tournait avec
`DEBUG = True`. En production, ce réglage expose à tout visiteur, à la moindre
erreur, la trace d'exception complète et la liste des routes de l'application.
C'est un défaut de sécurité réel, pas une coquette.

Passer `DEBUG` à `False` a immédiatement fait basculer les deux instances en
`unhealthy`, avec `Target.ResponseCodeMismatch`. Une session Session Manager —
sans aucun port SSH ouvert — a donné la trace :

```
ValueError: Missing staticfiles manifest entry for
            'heartcare/js/js/jquery.prettyPhoto.js'
```

Un template de l'application référence un fichier statique inexistant, avec un
`js/js/` dupliqué. Le stockage `CompressedManifestStaticFilesStorage` transforme
toute référence manquante en exception, donc en erreur 500 sur **toutes** les
pages. Avec `DEBUG = True`, Django affichait une page d'erreur au lieu de
planter ; le défaut était invisible.

La correction retenue est `CompressedStaticFilesStorage` : les fichiers
statiques restent compressés et servis par whitenoise, sans exiger que chacun
soit présent. Corriger le template de l'application aurait été plus propre, mais
sortait du périmètre d'un projet d'infrastructure.

Ce que cet épisode illustre : activer un réglage de sécurité révèle souvent des
défauts préexistants. Le bon réflexe est de corriger le défaut, pas de
désactiver le réglage.

---

## 7bis. Méthode de diagnostic

Plusieurs pannes de ce projet se ressemblaient : un message d'erreur désignait
une cause, et la cause réelle était ailleurs. La méthode qui a fini par
marcher mérite d'être explicitée, parce qu'elle est transposable.

### Tester chaque permission une par une

Face à `AccessDenied`, le réflexe est de conclure que « le service est
bloqué ». C'est presque toujours faux. Un SCP refuse des **actions**, pas des
services. Sur IAM, la liste réelle s'est révélée très différente de la
supposition :

| Supposé | Réel |
|---|---|
| « IAM est bloqué » | 3 actions sur 6 autorisées |
| « S3 est bloqué » | seule la lecture object-lock l'est ; le backend fonctionne |

Chaque test coûtait une commande et trente secondes. La supposition a coûté
plusieurs jours de travail sur un backend local inutile.

### Distinguer l'échec de l'application de l'échec de la lecture

Le piège le plus coûteux du projet : sous le SCP S3, une modification de
bucket **est réellement appliquée** côté AWS, mais le provider ne peut pas la
relire pour l'enregistrer dans l'état. Terraform replanifie donc la même
modification à l'exécution suivante, et échoue de nouveau — indéfiniment.

Le symptôme ressemble à « la modification ne passe pas ». La réalité était
« la modification est passée, mais on ne peut pas le constater ». Vérifier
directement l'état réel de la ressource a tranché :

```bash
aws s3api get-bucket-tagging --bucket heartcare-dev-342766168998
# Owner = DevOps Team  -> le tag était bien posé
```

### Comparer les entrées, pas seulement les sorties

Un `plan` local annonçait `No changes` tandis que le même `plan` échouait dans
le pipeline. L'infrastructure était identique ; les **entrées** ne l'étaient
pas. `terraform.tfvars` n'était pas versionné, le pipeline retombait donc sur
les valeurs par défaut des variables, et une seule différait : `owner`.

Ce tag figure sur toutes les ressources. Une variable de quatre mots suffisait
à faire replanifier l'infrastructure entière, donc à toucher les buckets, donc
à heurter le SCP.

### Accéder aux instances sans ouvrir de port

Les instances n'ont pas d'adresse publique et le bastion n'a jamais été
déployé. Session Manager, accordé par la politique IAM, a permis d'ouvrir une
session et d'exécuter des commandes à distance sans qu'aucun port SSH ne soit
ouvert :

```bash
aws ssm send-command --instance-ids <id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -50 /var/log/user-data.log"]'
```

C'est ainsi que la trace `Missing staticfiles manifest entry` a été obtenue —
l'erreur que `DEBUG = True` masquait.

## 8. Résultats des tests

Les neuf tests obligatoires et leurs résultats sont consignés en détail dans
[tests.md](tests.md). Synthèse :

| Test | Résultat |
|---|---|
| `terraform fmt -check -recursive` | aucune différence |
| `terraform validate` (dev, test, prod) | Success |
| `terraform plan` | aucune erreur, plan stable |
| Accès Web par l'URL de l'ALB | HTTP 200, page Heart Care |
| Répartition de charge | les deux instances servent les requêtes |
| Panne d'une instance | service maintenu, instance remplacée |
| Auto Scaling | capacité ajustée |
| Sécurité de la base depuis Internet | connexion refusée |
| `terraform destroy` | ressources supprimées |

---

## 9. Coûts

Environ **0,18 $ par heure**, soit 127 $ par mois en fonctionnement continu.

| Poste | Part de la facture |
|---|---:|
| NAT Gateways (×2) | 52 % |
| Load Balancer | 13 % |
| Instances EC2 (×2) | 12 % |
| RDS et stockage | 12 % |
| Adresses IPv4 publiques | 11 % |

Le crédit de 50 $ couvre environ 285 heures, soit une douzaine de jours. Les
instances EC2, que l'on imagine spontanément être le centre de coût, ne pèsent
que 12 % : ce sont les composants réseau managés qui dominent.

### 9.1 Le détail

| Ressource | Quantité | Tarif | Coût horaire | Coût mensuel |
|---|---:|---|---:|---:|
| NAT Gateway | 2 | 0,045 $/h | 0,0900 $ | 65,70 $ |
| Application Load Balancer | 1 | 0,0225 $/h | 0,0225 $ | 16,43 $ |
| Instances EC2 `t3.micro` | 2 | 0,0104 $/h | 0,0208 $ | 15,18 $ |
| Adresses IPv4 publiques | 4 | 0,005 $/h | 0,0200 $ | 14,60 $ |
| RDS `db.t3.micro` | 1 | 0,018 $/h | 0,0180 $ | 13,14 $ |
| Stockage RDS `gp3` | 20 Go | 0,115 $/Go/mois | 0,0032 $ | 2,30 $ |
| **Total** | | | **≈ 0,175 $/h** | **≈ 127 $/mois** |

### 9.2 Ce que couvre le crédit

| Durée | Coût |
|---|---:|
| 1 heure | 0,18 $ |
| 1 journée de travail (8 h) | 1,40 $ |
| 1 jour complet | 4,19 $ |
| 1 semaine | 29,33 $ |

### 9.3 Les arbitrages envisagés

| Levier | Économie | Contrepartie |
|---|---:|---|
| Détruire entre les sessions | jusqu'à 100 % | ~10 min de remise en route |
| Une seule NAT Gateway | 32,85 $/mois | sa zone devient un point de défaillance unique |
| Endpoints VPC pour S3 et SSM | ~30 $/mois | ne couvre ni APT ni GitHub |
| `desired_capacity = 1` en dev | 7,59 $/mois | plus de haute disponibilité, donc plus de test de panne |

Seul le premier a été retenu. Les trois autres dégradent précisément ce que le
projet doit démontrer, pour une économie qui ne change rien à l'échelle d'un
crédit de 50 $.

Le seul levier qui compte vraiment est donc de détruire l'environnement entre
deux sessions de travail. Détail dans [couts.md](couts.md).

---

## 9bis. Conformité au cahier des charges

Chaque exigence a été vérifiée par une commande, non par relecture. Synthèse.

| Section | Exigence | État | Preuve |
|---|---|---|---|
| 5, 7 | VPC sur 2 AZ, 6 sous-réseaux au plan donné | conforme | plan d'adressage identique au tableau |
| 5 | IGW, sortie contrôlée, ALB, LT + ASG, RDS privé, S3 | conforme | ressources vérifiées dans AWS |
| 5 | Rôles IAM de moindre privilège | partiel | politique créée, attachement refusé par SCP |
| 5 | Backend distant | conforme | S3 chiffré, versionné, verrouillé |
| 5 | Pipeline CI/CD | conforme | GitHub Actions, run vert |
| 8 | ALB accepte HTTP/HTTPS depuis Internet | conforme | `sg-alb` : 80 et 443 depuis `0.0.0.0/0` |
| 8 | App n'accepte que depuis le SG de l'ALB | conforme | règle lue dans AWS |
| 8 | Base n'accepte que depuis le SG applicatif | conforme | règle lue dans AWS |
| 8 | Aucun secret dans Git | conforme | `git grep` sans résultat |
| 8 | Buckets sans accès public | conforme | 4 verrous actifs sur 4 buckets |
| 8 | Chiffrement des données sensibles et de l'état | conforme | AES256 partout |
| 9 | URL fonctionnelle, 2 instances / 2 zones | conforme | HTTP 200 |
| 9 | Continuité après arrêt d'une instance | conforme | 30/30 réponses 200 |
| 9 | RDS injoignable depuis Internet | conforme | adresse privée, connexion refusée |
| 10, 11 | Structure du dépôt, 5 fichiers par module | conforme | 7 modules complets |
| 12 | Nommage, tags obligatoires, snake_case | conforme | tags lus sur le VPC |
| 13 | `required_version`, variables typées, validations | conforme | 11 fichiers, 158 descriptions, 12 validations |
| 16 | Les 6 exigences du backend | conforme | vérifiées une par une |
| 17 | Trois environnements, état séparé | conforme | 3 clés S3 distinctes |
| 19 | Les 9 étapes du pipeline | conforme | run vert, 0 avertissement |
| 21 | Serveur Web, nom d'hôte, répartition, Healthy | conforme | `/whoami`, 2 instances |
| 22 | Les 9 tests obligatoires | conforme | détaillés dans `tests.md` |
| 23 | Ni `.terraform` ni `tfstate` versionnés | conforme | `git ls-files` sans résultat |
| 24, 25 | Livrables et contenu du README | conforme | ce document et les autres |

Une seule ligne est marquée « partiel » : le moindre privilège IAM, dont
l'attachement au rôle est refusé par une SCP extérieure au compte. Le code est
en place pour lever la restriction dès qu'elle disparaît.

La règle « le Load Balancer accepte HTTP/HTTPS depuis Internet » appartient à
la section **8, Règles de sécurité minimales**, dont toutes les puces décrivent
des règles de Security Group. Elle porte donc sur le pare-feu de l'ALB, et non
sur ses listeners : `sg-alb` autorise bien 80 et 443 depuis `0.0.0.0/0`. Le
listener HTTPS, lui, relève du chiffrement en transit, traité en 4.5.

## 10. Bilan

### Ce qui fonctionne

L'infrastructure répond aux exigences : application accessible par l'ALB, deux
instances dans deux zones, service maintenu à la perte d'une instance, base
injoignable depuis Internet, état centralisé chiffré et versionné, pipeline
produisant un plan lisible avant toute application. Le code est modulaire,
documenté, formaté et validé.

### Ce qui reste ouvert

Le moindre privilège IAM est écrit mais pas appliqué à l'exécution, faute de
pouvoir créer un rôle sur ce compte. L'ALB n'écoute qu'en HTTP. L'emploi de
`-refresh=false` signifie que Terraform ne détecte pas une dérive introduite à
la main dans la console AWS — à retirer sur un compte sans la SCP concernée.

Un seul point reste à reprendre à chaque session : les identifiants AWS du
Learner Lab expirent, et les secrets GitHub doivent être rafraîchis pour que le
pipeline puisse s'authentifier.

### Ce que le projet nous a appris

**Un message d'erreur d'autorisation ne dit pas ce qui est bloqué, seulement
quelle API a été refusée.** Nous avons abandonné le backend S3 pendant
plusieurs jours sur la foi d'un `AccessDenied` qui ne le concernait pas. Tester
chaque action une par une a transformé « IAM est bloqué » en une liste précise
où la majorité des actions étaient en fait autorisées.

**Les contraintes d'un environnement masquent les défauts de son propre code.**
Le diff perpétuel causé par `timestamp()` a été attribué à la SCP pendant
longtemps, alors qu'il venait de nos propres tags.

**Déployer une application réelle apprend davantage qu'une page de test.** Le
conflit de ports, `DEBUG = True` et le manifeste de fichiers statiques sont
trois problèmes qu'un `echo` dans `index.html` n'aurait jamais révélés.

---

## Annexes

| Document | Contenu |
|---|---|
| [architecture.md](architecture.md) | Schéma, Security Groups, routage, flux |
| [securite.md](securite.md) | Justification des choix de sécurité |
| [couts.md](couts.md) | Estimation détaillée et leviers de réduction |
| [tests.md](tests.md) | Procédures et résultats des tests obligatoires |
| [../README.md](../README.md) | Prérequis, procédures, dépannage |
