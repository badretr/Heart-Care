# Module `network`

Socle réseau du projet : un VPC réparti sur deux zones de disponibilité, les
trois étages de sous-réseaux (public, applicatif privé, base de données privée),
la passerelle Internet et les sorties contrôlées des sous-réseaux privés.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_vpc.main` | VPC principal, DNS activé |
| `aws_internet_gateway.main` | Entrée/sortie Internet des sous-réseaux publics |
| `aws_subnet.public` (×2) | ALB et composants d'accès |
| `aws_subnet.private_app` (×2) | Instances applicatives, sans IP publique |
| `aws_subnet.private_db` (×2) | Groupe de sous-réseaux RDS |
| `aws_eip.nat` + `aws_nat_gateway.main` (×2) | Sortie Internet des sous-réseaux privés, une par AZ |
| `aws_route_table.*` + associations | Routage des trois étages |

Les sous-réseaux sont créés avec `count` sur la liste des zones, ce qui permet
de passer de deux à trois AZ sans toucher au code.

## Choix de conception

- **Une NAT Gateway par zone.** Une seule NAT coûterait moins cher mais
  ferait de sa zone un point de défaillance unique pour le trafic sortant de
  toutes les instances. C'est le poste de coût principal du projet
  (voir [docs/couts.md](../../../docs/couts.md)).
- **Les sous-réseaux DB ont leur propre table de routage, sans route par
  défaut vers Internet.** La base n'a aucun besoin de sortir ; lui retirer la
  route est plus sûr que de compter uniquement sur le Security Group.

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `vpc_cidr` | `string` | `10.20.0.0/16` | Bloc réseau principal |
| `availability_zones` | `list(string)` | `["us-east-1a","us-east-1b"]` | Zones utilisées |
| `public_subnet_cidrs` | `list(string)` | `["10.20.1.0/24","10.20.2.0/24"]` | Sous-réseaux publics |
| `private_app_subnet_cidrs` | `list(string)` | `["10.20.11.0/24","10.20.12.0/24"]` | Sous-réseaux applicatifs |
| `private_db_subnet_cidrs` | `list(string)` | `["10.20.21.0/24","10.20.22.0/24"]` | Sous-réseaux base de données |
| `environment` | `string` | — | Nom de l'environnement |
| `project_name` | `string` | — | Préfixe de nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_app_subnet_ids`,
`private_db_subnet_ids`, `internet_gateway_id`, `nat_gateway_ids`,
`availability_zones`

## Exemple

```hcl
module "network" {
  source = "../../modules/network"

  vpc_cidr                 = "10.20.0.0/16"
  availability_zones       = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs      = ["10.20.1.0/24", "10.20.2.0/24"]
  private_app_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
  private_db_subnet_cidrs  = ["10.20.21.0/24", "10.20.22.0/24"]
  environment              = "dev"
  project_name             = "heartcare"
  owner                    = "DevOps"
  common_tags              = local.common_tags
}
```
