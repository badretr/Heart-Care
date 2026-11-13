# Module `load-balancer`

Application Load Balancer public, son listener HTTP et le Target Group vers
lequel l'Auto Scaling Group enregistre les instances.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_lb.main` | ALB public, réparti sur les deux sous-réseaux publics |
| `aws_lb_target_group.app` | Cible HTTP port 8000, health check configurable |
| `aws_lb_listener.http` | Écoute le port 80 et transmet au Target Group |

## Choix de conception

- L'ALB est le **seul** composant exposé à Internet. Les instances n'ont pas
  d'adresse publique et ne sont joignables que par son Security Group.
- Le health check interroge `/` par défaut. L'application Heart Care expose
  aussi `/health/`, servi directement par nginx sans passer par Django : c'est
  la valeur à utiliser si l'on veut que le health check reste vert pendant un
  redémarrage applicatif.
- Seul le port 80 est écouté. Ajouter HTTPS demande un certificat ACM et un
  nom de domaine, hors périmètre du lab ; le Security Group de l'ALB autorise
  déjà 443 pour que l'ajout du listener soit la seule modification nécessaire.

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `vpc_id` | `string` | — | VPC cible |
| `public_subnet_ids` | `list(string)` | — | Sous-réseaux publics de l'ALB |
| `alb_security_group_id` | `string` | — | Security Group de l'ALB |
| `environment` | `string` | — | Nom de l'environnement |
| `project_name` | `string` | — | Préfixe de nommage |
| `health_check_path` | `string` | `/` | Chemin interrogé |
| `health_check_interval` | `number` | `30` | Intervalle, en secondes |
| `health_check_timeout` | `number` | `5` | Délai d'attente, en secondes |
| `health_check_healthy_threshold` | `number` | `2` | Succès avant passage à `healthy` |
| `health_check_unhealthy_threshold` | `number` | `2` | Échecs avant passage à `unhealthy` |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`alb_arn`, `alb_dns_name`, `alb_zone_id`, `target_group_arn`,
`target_group_name`, `alb_url`

## Exemple

```hcl
module "load_balancer" {
  source = "../../modules/load-balancer"

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  health_check_path     = "/health/"
  environment           = "dev"
  project_name          = "heartcare"
  common_tags           = local.common_tags
}
```
