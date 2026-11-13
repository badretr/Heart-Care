# Module `load-balancer`

Application Load Balancer public, son listener HTTP et le Target Group vers
lequel l'Auto Scaling Group enregistre les instances.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_lb.main` | ALB public, réparti sur les deux sous-réseaux publics |
| `aws_lb_target_group.app` | Cible HTTP port 8000, health check configurable |
| `aws_lb_listener.http` | Écoute le port 80 et transmet au Target Group |
| `aws_lb_listener.https` | Écoute le port 443 — créé si `certificate_arn` est fourni |
| `aws_lb_listener_rule.redirect_https` | Redirige HTTP vers HTTPS — même condition |

## Choix de conception

- L'ALB est le **seul** composant exposé à Internet. Les instances n'ont pas
  d'adresse publique et ne sont joignables que par son Security Group.
- Le health check interroge `/` par défaut. L'application Heart Care expose
  aussi `/health/`, servi directement par nginx sans passer par Django : c'est
  la valeur à utiliser si l'on veut que le health check reste vert pendant un
  redémarrage applicatif.
- **HTTPS est piloté par `certificate_arn`.** Vide, le module n'écoute qu'en
  HTTP. Renseigné, il crée le listener 443 *et* redirige le port 80 vers lui,
  en HTTP 301. Le `count` sur les deux ressources évite d'avoir à maintenir
  deux variantes du module.
- La variable reste vide par défaut parce qu'un certificat suppose un nom de
  domaine : le nom DNS d'un ALB appartient à `amazonaws.com`, qu'ACM ne peut
  pas valider. Les deux voies possibles sont décrites dans
  [docs/securite.md](../../../docs/securite.md).

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
| `certificate_arn` | `string` | `""` | Certificat ACM ; vide = pas de listener HTTPS |
| `ssl_policy` | `string` | `ELBSecurityPolicy-TLS13-1-2-2021-06` | Politique TLS du listener HTTPS |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`alb_arn`, `alb_dns_name`, `alb_zone_id`, `target_group_arn`,
`target_group_name`, `alb_url`, `https_enabled`

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
