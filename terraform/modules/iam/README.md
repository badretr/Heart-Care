# Module `iam`

Politique de moindre privilège des instances applicatives, rôle associé et
instance profile rattaché au Launch Template.

## Ce que le module crée

| Ressource | Condition | Rôle |
|---|---|---|
| `aws_iam_policy.app` | toujours | Politique de moindre privilège |
| `aws_iam_role.app` | `create_iam_role = true` | Rôle assumé par EC2 |
| `aws_iam_role_policy_attachment.app` | `create_iam_role = true` | Rattache la politique au rôle |
| `data.aws_iam_role.existing` | `create_iam_role = false` | Rôle pré-provisionné réutilisé |
| `aws_iam_instance_profile.app` | toujours | Instance profile porté par les instances |

## La politique de moindre privilège

| Déclaration | Autorise | Portée |
|---|---|---|
| `AppBucketObjectAccess` | `s3:GetObject`, `PutObject`, `DeleteObject` | objets du seul bucket applicatif |
| `AppBucketList` | `s3:ListBucket`, `GetBucketLocation` | le seul bucket applicatif |
| `LogsBucketWrite` | `s3:PutObject` | objets du seul bucket de journaux |
| `ParameterStoreRead` | `ssm:GetParameter*` | `/<projet>/<environnement>/*` |
| `DecryptParameters` | `kms:Decrypt` | restreint par `kms:ViaService = ssm` |
| `CloudWatchLogsWrite` | `logs:CreateLogStream`, `PutLogEvents` | groupes `/aws/ec2/<projet>-<env>*` |
| `SessionManager` | canaux `ssmmessages` | accès administratif sans port SSH ouvert |

Aucune déclaration n'emploie `Action: "*"`, et les seules ressources en `*`
(`kms:Decrypt`, Session Manager) sont des API qui n'acceptent pas d'ARN ; la
première est bornée par une condition.

## Limites sur AWS Academy Learner Lab

Les permissions ont été vérifiées une par une sur le compte :

| Action | État |
|---|---|
| `iam:CreatePolicy` | autorisée |
| `iam:CreateInstanceProfile` | autorisée |
| `iam:AddRoleToInstanceProfile` | autorisée |
| `iam:CreateRole` | **refusée** |
| `iam:AttachRolePolicy` | **refusée** |
| `iam:TagPolicy`, `iam:TagInstanceProfile` | **refusées** |

Deux conséquences, toutes deux pilotées par variable pour que le code reste
applicable tel quel sur un compte AWS standard :

1. **`create_iam_role = false`** (défaut) : le rôle n'est pas créé et
   l'instance profile est rattaché au rôle existant `existing_role_name`
   (`LabRole`). La politique est bien créée, mais ne peut pas être rattachée ;
   la sortie `policy_attached_to_role` le signale explicitement. Sur un compte
   standard, `create_iam_role = true` crée le rôle, rattache la politique, et
   le moindre privilège s'applique réellement à l'exécution.
2. **`enable_iam_tags = false`** (défaut) : les ressources IAM sont créées sans
   tags. Elles passent par un provider aliasé `aws.untagged`, sans
   `default_tags`, sinon les tags injectés globalement par le provider
   principal déclencheraient `iam:TagPolicy` et feraient échouer la création.

L'environnement appelant doit donc passer ce provider :

```hcl
provider "aws" {
  alias  = "untagged"
  region = var.aws_region
}
```

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `app_bucket_arn` | `string` | — | Bucket applicatif accessible en lecture/écriture |
| `logs_bucket_arn` | `string` | — | Bucket de journaux accessible en écriture |
| `create_iam_role` | `bool` | `false` | Créer le rôle ; `false` sur Learner Lab |
| `existing_role_name` | `string` | `LabRole` | Rôle réutilisé si `create_iam_role = false` |
| `enable_iam_tags` | `bool` | `false` | Taguer les ressources IAM ; `false` sur Learner Lab |
| `environment`, `project_name` | `string` | — | Nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`app_policy_arn`, `app_policy_name`, `app_role_name`, `app_role_arn`,
`app_instance_profile_name`, `app_instance_profile_arn`,
`policy_attached_to_role`

## Exemple

```hcl
module "iam" {
  source = "../../modules/iam"

  providers = {
    aws.untagged = aws.untagged
  }

  app_bucket_arn  = module.storage.s3_bucket_arn
  logs_bucket_arn = module.storage.s3_logs_bucket_arn

  # Sur un compte AWS standard, passer les deux à true.
  create_iam_role = false
  enable_iam_tags = false

  environment  = "dev"
  project_name = "heartcare"
  common_tags  = local.common_tags
}
```
