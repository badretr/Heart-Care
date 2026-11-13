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

### 2.3 Deux décisions structurantes

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

### 3.3 Qualité du code

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

### 4.5 Points ouverts, assumés

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

Le job de verification tourne **en matrice sur les trois environnements**, ce
qui garantit que `test` et `prod` restent valides même s'ils ne sont pas
déployés.

**Application**, sous conditions : `dev` s'applique sur un push vers `main` ;
`test` et `prod` ne s'appliquent que sur déclenchement manuel
(`workflow_dispatch`), depuis `main`. Aucun push ne peut déployer `prod`.

Une Pull Request produit donc trois plans consultables sans jamais rien
appliquer, ce qui est le comportement demandé.

**Une réserve subsiste.** L'approbation par un relecteur repose sur les
protections de l'environnement GitHub, et le dépôt n'en déclare aujourd'hui
aucun. GitHub crée alors l'environnement à la volée, sans protection : le
déploiement reste manuel, mais non approuvé. Créer les environnements et y
cocher *Required reviewers* est une manipulation d'interface de deux minutes,
documentée dans le README, mais elle n'est pas faite à l'heure de ce rapport.
La distinction mérite d'être posée : le workflow garantit par construction
qu'aucun push ne déploie `prod` ; il ne peut pas, seul, imposer qu'un humain
approuve.

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

### 6.4 Un diff perpétuel qui bloquait S3

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

Le seul levier qui compte vraiment est de détruire l'environnement entre deux
sessions de travail. Détail dans [couts.md](couts.md).

---

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

Deux réglages relèvent de l'interface GitHub et restent à faire : rafraîchir
les secrets AWS, qui expirent à chaque session du Learner Lab, et créer les
environnements `dev`, `test` et `prod` avec des relecteurs obligatoires sur les
deux derniers.

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
