# Module `compute`

Launch Template, Auto Scaling Group et politiques de mise à l'échelle des
instances applicatives.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `data.aws_ami.ubuntu` | Dernière AMI Ubuntu 22.04 officielle |
| `aws_launch_template.app` | Gabarit d'instance : AMI, type, SG, instance profile, `user_data` |
| `aws_autoscaling_group.app` | Groupe réparti sur les deux sous-réseaux applicatifs |
| `aws_autoscaling_policy.scale_up` / `scale_down` | Ajout et retrait d'une instance |
| `aws_cloudwatch_metric_alarm.cpu_high` / `cpu_low` | Déclencheurs des politiques |

## `user_data.sh`

Le script déployé sur chaque instance installe nginx, Python et l'application
Heart Care depuis son dépôt Git, puis :

- installe Django, gunicorn et whitenoise dans un environnement virtuel ;
- complète `settings.py` avec les réglages de production (`ALLOWED_HOSTS`,
  `STATIC_ROOT`, middleware whitenoise) ;
- lance `collectstatic` et `migrate` ;
- configure **nginx sur le port 8000** en frontal, qui sert les fichiers
  statiques, répond directement sur `/health/` et transmet le reste à
  **gunicorn sur 127.0.0.1:8001** ;
- enregistre gunicorn comme service systemd `heartcare`, avec `Restart=always`.

La séparation des ports compte : nginx et gunicorn écoutaient tous deux sur
8000 dans une version antérieure, et gunicorn ne démarrait pas, ce qui donnait
un `502 Bad Gateway` au travers de l'ALB.

## Choix de conception

- **`health_check_type = "ELB"`** et non `"EC2"` : l'ASG remplace une instance
  dont l'application ne répond plus, pas seulement une instance éteinte.
- **`health_check_grace_period = 300`** laisse au `user_data` le temps
  d'installer l'application avant le premier verdict.
- Les instances n'ont **pas d'adresse IP publique** ; elles joignent Internet
  par les NAT Gateways pour récupérer paquets et code.

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `private_app_subnet_ids` | `list(string)` | — | Sous-réseaux de l'ASG |
| `app_security_group_id` | `string` | — | Security Group applicatif |
| `target_group_arn` | `string` | — | Target Group d'enregistrement |
| `iam_instance_profile_name` | `string` | — | Instance profile (module `iam`) |
| `instance_type` | `string` | `t3.micro` | Type d'instance |
| `min_size` | `number` | `2` | Minimum, validé entre 1 et 10 |
| `max_size` | `number` | `4` | Maximum, validé entre 1 et 10 |
| `desired_capacity` | `number` | `2` | Capacité souhaitée, validée entre 1 et 10 |
| `health_check_type` | `string` | `ELB` | Type de health check de l'ASG |
| `health_check_grace_period` | `number` | `300` | Délai de grâce, en secondes |
| `db_host`, `db_name`, `db_user` | `string` | — / `heartcare` | Connexion base passée au `user_data` |
| `ami_id` | `string` | `""` | AMI explicite ; vide = dernière Ubuntu 22.04 |
| `environment`, `project_name` | `string` | — | Nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`launch_template_id`, `launch_template_latest_version`,
`autoscaling_group_name`, `autoscaling_group_arn`, `autoscaling_group_min_size`,
`autoscaling_group_max_size`, `autoscaling_group_desired_capacity`

## Exemple

```hcl
module "compute" {
  source = "../../modules/compute"

  private_app_subnet_ids    = module.network.private_app_subnet_ids
  app_security_group_id     = module.security.app_security_group_id
  target_group_arn          = module.load_balancer.target_group_arn
  iam_instance_profile_name = module.iam.app_instance_profile_name
  instance_type             = "t3.micro"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  db_host                   = split(":", module.database.db_instance_endpoint)[0]
  environment               = "dev"
  project_name              = "heartcare"
  common_tags               = local.common_tags
}
```
