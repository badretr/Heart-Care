# Schéma d'architecture

## Vue d'ensemble

```
                                  INTERNET
                                      │
                      ┌───────────────┴───────────────┐
                      │                               │
                  HTTP :80                      (aucun accès direct
                      │                          aux étages privés)
┌─────────────────────▼───────────────────────────────────────────────────────┐
│ VPC  heartcare-dev-vpc        10.20.0.0/16            région us-east-1       │
│                                                                             │
│  ┌─────────── us-east-1a ───────────┐  ┌─────────── us-east-1b ───────────┐  │
│  │                                  │  │                                  │  │
│  │  SOUS-RÉSEAU PUBLIC              │  │  SOUS-RÉSEAU PUBLIC              │  │
│  │  10.20.1.0/24                    │  │  10.20.2.0/24                    │  │
│  │  ┌────────────────────────────┐  │  │  ┌────────────────────────────┐  │  │
│  │  │  ALB (nœud)   ◄── sg-alb   │  │  │  │  ALB (nœud)   ◄── sg-alb   │  │  │
│  │  └─────────────┬──────────────┘  │  │  └─────────────┬──────────────┘  │  │
│  │  ┌─────────────┴──────────────┐  │  │  ┌─────────────┴──────────────┐  │  │
│  │  │  NAT Gateway + EIP         │  │  │  │  NAT Gateway + EIP         │  │  │
│  │  └─────────────┬──────────────┘  │  │  └─────────────┬──────────────┘  │  │
│  │                │                 │  │                │                 │  │
│  ├────────────────┼─────────────────┤  ├────────────────┼─────────────────┤  │
│  │                │                 │  │                │                 │  │
│  │  SOUS-RÉSEAU APP PRIVÉ           │  │  SOUS-RÉSEAU APP PRIVÉ           │  │
│  │  10.20.11.0/24                   │  │  10.20.12.0/24                   │  │
│  │  ┌────────────▼───────────────┐  │  │  ┌────────────▼───────────────┐  │  │
│  │  │  EC2 t3.micro ◄── sg-app   │  │  │  │  EC2 t3.micro ◄── sg-app   │  │  │
│  │  │  nginx       :8000         │  │  │  │  nginx       :8000         │  │  │
│  │  │  gunicorn    :8001         │  │  │  │  gunicorn    :8001         │  │  │
│  │  │  pas d'IP publique         │  │  │  │  pas d'IP publique         │  │  │
│  │  └────────────┬───────────────┘  │  │  └────────────┬───────────────┘  │  │
│  │               │                  │  │               │                  │  │
│  ├───────────────┼──────────────────┤  ├───────────────┼──────────────────┤  │
│  │               │                  │  │               │                  │  │
│  │  SOUS-RÉSEAU DB PRIVÉ            │  │  SOUS-RÉSEAU DB PRIVÉ            │  │
│  │  10.20.21.0/24                   │  │  10.20.22.0/24                   │  │
│  │  ┌────────────▼───────────────┐  │  │  ┌────────────────────────────┐  │  │
│  │  │  RDS PostgreSQL 15         │  │  │  │  (réservé au basculement   │  │  │
│  │  │  :5432   ◄── sg-rds        │  │  │  │   Multi-AZ)                │  │  │
│  │  │  chiffré · non public      │  │  │  │                            │  │  │
│  │  │  AUCUNE route Internet     │  │  │  │                            │  │  │
│  │  └────────────────────────────┘  │  │  └────────────────────────────┘  │  │
│  └──────────────────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘

   Hors VPC, régionaux :
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │  S3 appli    │  │  S3 journaux │  │  SSM Param   │  │  S3 état TF  │
   │  versionné   │  │              │  │  SecureString│  │  + verrou    │
   │  chiffré     │  │              │  │              │  │  + versions  │
   └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
```

## Chaîne des Security Groups

Chaque règle entrante désigne un **Security Group source**, jamais une plage
d'adresses. L'accès découle de l'appartenance à un groupe, pas d'une position
dans le réseau.

```
  Internet          sg-alb            sg-app            sg-rds
     │                 │                 │                 │
     ├── :80, :443 ───►│                 │                 │
     │                 ├──── :8000 ─────►│                 │
     │                 │                 ├──── :5432 ─────►│
     │                 │                 │                 │
  sg-bastion           │                 │                 │
     ├──── :22 ────────┼────────────────►│                 │
```

| Security Group | Port | Source autorisée |
|---|---|---|
| `sg-alb` | 80, 443 | `0.0.0.0/0` |
| `sg-app` | 8000 | `sg-alb` |
| `sg-app` | 22 | `sg-bastion` |
| `sg-rds` | 5432 | `sg-app` |

## Routage

| Table de routage | Sous-réseaux | Route par défaut |
|---|---|---|
| `rtb-public` | publics A et B | Internet Gateway |
| `rtb-private-app-a` | app A | NAT Gateway de la zone A |
| `rtb-private-app-b` | app B | NAT Gateway de la zone B |
| `rtb-private-db` | DB A et B | **aucune** |

L'absence de route par défaut sur les sous-réseaux de base de données est une
seconde barrière, indépendante des Security Groups : même une règle de pare-feu
erronée ne rendrait pas la base joignable depuis l'extérieur, faute de chemin.

## Chemin d'une requête

```
1.  Navigateur          GET http://<alb-dns>/
2.  ALB                 sg-alb accepte le port 80 depuis Internet
3.  ALB                 choisit une cible saine du Target Group
4.  EC2 · nginx :8000   sg-app accepte 8000 depuis sg-alb uniquement
5.  nginx               /static/ servi directement depuis le disque
                        /health/ et /whoami répondus par nginx
                        le reste transmis à gunicorn
6.  gunicorn :8001      Django traite la requête
7.  RDS :5432           sg-rds accepte 5432 depuis sg-app uniquement
8.  réponse             remonte la même chaîne jusqu'au navigateur
```

## Haute disponibilité

| Panne | Comportement |
|---|---|
| Une instance EC2 | L'ALB la retire du Target Group après 2 échecs ; l'ASG en démarre une autre |
| Une zone de disponibilité | L'autre zone porte l'ALB, une instance et sa NAT Gateway |
| Le processus gunicorn | `Restart=always` dans systemd le relance |
| La base de données | Point de défaillance unique en `dev` ; `multi_az = true` en `prod` |

## Flux de déploiement

```
Développeur
    │ git push
    ▼
Dépôt GitHub
    │ déclenche
    ▼
GitHub Actions ──── job terraform-ci ─────────────────────────┐
    │                 fmt → init → validate → plan → artefact │
    │                                                         │
    │ si push sur main ET job précédent réussi                │
    ▼                                                         │
job terraform-apply ◄── environnement « production »          │
    │                   (approbation manuelle possible)       │
    │ terraform apply                                         │
    ▼                                                         │
AWS ── réseau · load balancer · auto scaling · base · stockage ┘
```

Une Pull Request produit un plan consultable en artefact, sans jamais appliquer
quoi que ce soit.

## État Terraform

```
s3://heartcare-terraform-state-<compte>/
├── dev/terraform.tfstate      ─┐
├── test/terraform.tfstate       ├── chiffré · versionné · verrou natif S3
└── prod/terraform.tfstate     ─┘
```

Un état par environnement : une erreur sur `dev` ne peut pas corrompre `prod`.
