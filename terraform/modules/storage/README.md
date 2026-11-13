# Module `storage`

Bucket S3 applicatif et bucket de journaux, avec versioning, chiffrement,
blocage de l'accès public et règles de cycle de vie.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_s3_bucket.main` | Bucket applicatif, nommé avec l'identifiant de compte |
| `aws_s3_bucket_versioning.main` | Versioning des objets |
| `aws_s3_bucket_server_side_encryption_configuration.main` | Chiffrement AES256 |
| `aws_s3_bucket_public_access_block.main` | Blocage complet de l'accès public |
| `aws_s3_bucket_policy.main` | Refus explicite du trafic non chiffré |
| `aws_s3_bucket_lifecycle_configuration.main` | Expiration des versions anciennes |
| `aws_s3_bucket_logging.main` | Journaux d'accès vers le bucket de logs |
| `aws_s3_bucket.logs` + ses règles | Bucket de journaux, mêmes protections |

## Choix de conception

- Le nom du bucket intègre `data.aws_caller_identity.current.account_id` :
  l'espace de noms S3 est mondial, et le projet doit pouvoir être déployé par
  une autre équipe sur un autre compte sans collision.
- **Les deux buckets bloquent l'accès public**, sans exception (exigence 8).
- La politique du bucket refuse les requêtes dont `aws:SecureTransport` est
  faux, ce qui interdit l'accès en HTTP simple.
- Les versions non courantes expirent après `lifecycle_expiration_days` afin
  que le versioning ne fasse pas croître le coût indéfiniment.

## Limite connue sur AWS Academy

Une SCP d'organisation refuse `s3:GetBucketObjectLockConfiguration`, que le
provider AWS appelle à chaque lecture d'une ressource `aws_s3_bucket`. Tant que
l'état d'un bucket est complet et qu'aucune modification n'est planifiée sur la
ressource elle-même, les `plan` et `apply` passent. En revanche un `refresh`,
un `import` ou toute modification du bloc `aws_s3_bucket` échouent. D'où
l'emploi de `-refresh=false` dans le pipeline, détaillé dans
[docs/securite.md](../../../docs/securite.md).

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `enable_versioning` | `bool` | `true` | Versioning du bucket applicatif |
| `enable_encryption` | `bool` | `true` | Chiffrement au repos |
| `block_public_access` | `bool` | `true` | Blocage de l'accès public |
| `lifecycle_expiration_days` | `number` | `90` | Expiration des versions non courantes |
| `environment`, `project_name` | `string` | — | Nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`s3_bucket_id`, `s3_bucket_arn`, `s3_bucket_regional_domain_name`,
`s3_logs_bucket_id`, `s3_logs_bucket_arn`

## Exemple

```hcl
module "storage" {
  source = "../../modules/storage"

  enable_versioning = true
  enable_encryption = true
  environment       = "dev"
  project_name      = "heartcare"
  common_tags       = local.common_tags
}
```
