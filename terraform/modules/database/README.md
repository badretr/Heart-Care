# Module `database`

Instance RDS PostgreSQL placée dans les sous-réseaux privés, son groupe de
sous-réseaux, son groupe de paramètres et les paramètres SSM associés.

## Ce que le module crée

| Ressource | Rôle |
|---|---|
| `aws_db_subnet_group.main` | Groupe sur les deux sous-réseaux privés DB |
| `aws_db_instance.main` | PostgreSQL 15, chiffré, non public |
| `aws_db_parameter_group.main` | Journalisation des requêtes lentes (> 1 s) |
| `aws_ssm_parameter.db_password_actual` | Mot de passe en `SecureString` |
| `aws_ssm_parameter.db_connection_string` | Chaîne de connexion sans mot de passe |

## Choix de conception

- **`publicly_accessible = false`** et aucun sous-réseau DB ne porte de route
  vers Internet : la base est injoignable depuis l'extérieur, ce que le test
  de sécurité de [docs/tests.md](../../../docs/tests.md) vérifie.
- **`storage_encrypted = true`** : chiffrement au repos (exigence 8).
- **`iam_database_authentication_enabled = true`** : permet à terme de se
  connecter par jeton IAM plutôt que par mot de passe.
- Le mot de passe arrive par la variable `db_password`, marquée `sensitive`,
  alimentée par `TF_VAR_db_password` depuis le coffre du pipeline. Il
  n'apparaît ni dans le dépôt, ni dans les journaux.
- `skip_final_snapshot = true` et `deletion_protection = false` : adaptés à un
  environnement de démonstration que l'on détruit à la fin. **À inverser pour
  un environnement de production.**
- Performance Insights et le monitoring amélioré sont désactivés : ils sont
  facturés et le monitoring amélioré exige un rôle IAM que le Learner Lab ne
  permet pas de créer.

## Entrées

| Variable | Type | Défaut | Description |
|---|---|---|---|
| `private_db_subnet_ids` | `list(string)` | — | Sous-réseaux du groupe DB |
| `rds_security_group_id` | `string` | — | Security Group RDS |
| `db_name` | `string` | `heartcare` | Nom de la base |
| `db_username` | `string` | `heartcare` | Utilisateur maître |
| `db_password` | `string` (sensible) | — | Mot de passe maître |
| `db_instance_class` | `string` | `db.t3.micro` | Classe d'instance |
| `allocated_storage` | `number` | `20` | Stockage, en Go |
| `storage_type` | `string` | `gp3` | Type de stockage |
| `engine_version` | `string` | `15.19` | Version PostgreSQL |
| `backup_retention_days` | `number` | `7` | Rétention des sauvegardes |
| `backup_window` | `string` | `03:00-04:00` | Fenêtre de sauvegarde |
| `maintenance_window` | `string` | `sun:04:00-sun:05:00` | Fenêtre de maintenance |
| `multi_az` | `bool` | `false` | Déploiement multi-AZ |
| `enable_encryption` | `bool` | `true` | Chiffrement au repos |
| `enable_cloudwatch_logs` | `bool` | `true` | Export des journaux PostgreSQL |
| `environment`, `project_name` | `string` | — | Nommage |
| `owner` | `string` | `DevOps` | Propriétaire (tag) |
| `common_tags` | `map(string)` | `{}` | Tags communs |

## Sorties

`db_instance_id`, `db_instance_endpoint`, `db_instance_address`,
`db_instance_port`, `db_name`, `db_username`, `db_connection_string`,
`db_password_parameter_name`, `db_subnet_group_name`

## Exemple

```hcl
module "database" {
  source = "../../modules/database"

  private_db_subnet_ids = module.network.private_db_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_instance_class     = "db.t3.micro"
  allocated_storage     = 20
  db_password           = var.db_password  # via TF_VAR_db_password
  multi_az              = false
  environment           = "dev"
  project_name          = "heartcare"
  common_tags           = local.common_tags
}
```
