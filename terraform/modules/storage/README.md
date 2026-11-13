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
provider AWS appelle à chaque lecture d'une ressource `aws_s3_bucket` — y
compris juste après une mise à jour. Toute modification du bloc
`aws_s3_bucket` échoue donc, de même qu'un `refresh` ou un `import`.

Le piège est subtil : la modification **est bien appliquée** côté AWS, mais
Terraform ne peut pas en prendre acte, replanifie la même modification à
l'exécution suivante, et échoue de nouveau. Un simple changement de tag suffit
à bloquer définitivement l'`apply`.

Les deux buckets déclarent donc :

```hcl
lifecycle {
  ignore_changes = [tags, tags_all]
}
```

Les tags restent corrects côté AWS, posés à la création, et vérifiables par
`aws s3api get-bucket-tagging --bucket <nom>`.

## Créer un environnement neuf : l'étape de `untaint`

`ignore_changes` règle le cas des mises à jour, mais **pas celui de la
création**. Quand Terraform crée un bucket pour la première fois, il le relit
aussitôt pour enregistrer ses attributs. Cette lecture échoue, et Terraform
marque alors la ressource **tainted** : au `plan` suivant, il veut la
remplacer, c'est-à-dire la détruire puis la recréer — ce qui échouerait de la
même façon, indéfiniment.

Le bucket existe pourtant bel et bien dans AWS, correctement configuré. Il
suffit de retirer la marque :

```bash
terraform untaint module.storage.aws_s3_bucket.main
terraform untaint module.storage.aws_s3_bucket.logs
terraform apply -refresh=false
```

Le second `apply` crée alors les sous-ressources qui dépendent des buckets —
versioning, chiffrement, blocage public, cycle de vie, journalisation,
politique — et le plan redevient stable.

**Cette étape n'est nécessaire qu'au premier déploiement d'un environnement**,
et uniquement sur un compte soumis à cette SCP. **À retirer sur un compte AWS
sans cette SCP.** Le pipeline emploie par ailleurs `-refresh=false`, détaillé
dans [docs/securite.md](../../../docs/securite.md).

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
