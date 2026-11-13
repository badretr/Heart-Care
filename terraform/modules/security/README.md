# Module `security`

Security Groups du projet et paramètre SSM du mot de passe de base de données.
Les rôles et politiques IAM sont gérés par le module
[`iam`](../iam/README.md), séparé parce que ses ressources ont besoin d'un
provider distinct (voir ce README).

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_security_group.alb` | Accepte 80 et 443 depuis Internet |
| `aws_security_group.app` | Accepte 8000 **depuis le SG de l'ALB uniquement**, 22 depuis le SG bastion |
| `aws_security_group.rds` | Accepte 5432 **depuis le SG applicatif uniquement** |
| `aws_security_group.bastion` | Accès administratif SSH |
| `aws_ssm_parameter.db_password` | Emplacement `SecureString` du mot de passe |

## Choix de conception

Les règles entrantes se réfèrent à des **Security Groups sources**, jamais à
des plages CIDR. Une instance ne peut donc joindre la base que parce qu'elle
porte le SG applicatif, pas parce qu'elle se trouve dans un certain
sous-réseau : la règle reste correcte même si le plan d'adressage change.

Le paramètre SSM utilise `lifecycle { ignore_changes = [value] }`. Terraform
crée l'emplacement, mais la valeur réelle y est injectée hors du code, de sorte
qu'aucun secret ne transite par le dépôt (exigence 8 du cahier des charges).

Le Security Group bastion ouvre le port 22 depuis `0.0.0.0/0`. C'est une
ouverture volontairement large, à restreindre à l'adresse IP de
l'administrateur avant tout usage réel ; elle est documentée dans
[docs/securite.md](../../../docs/securite.md).

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `vpc_id` | `string` | — | VPC où créer les Security Groups |
| `environment` | `string` | — | Nom de l'environnement |
| `project_name` | `string` | — | Préfixe de nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`alb_security_group_id`, `app_security_group_id`, `rds_security_group_id`,
`bastion_security_group_id`, `db_password_parameter_name`

## Exemple

```hcl
module "security" {
  source = "../../modules/security"

  vpc_id       = module.network.vpc_id
  environment  = "dev"
  project_name = "heartcare"
  owner        = "DevOps"
  common_tags  = local.common_tags
}
```
