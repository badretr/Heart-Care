locals {
  common_tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  )

  name_prefix = "${var.project_name}-${var.environment}"

  # AWS Academy Learner Lab refuse iam:TagPolicy et iam:TagInstanceProfile.
  # Les ressources IAM sont donc creees sans tags dans le lab ; sur un compte
  # AWS standard, enable_iam_tags = true applique les tags obligatoires.
  iam_tags = var.enable_iam_tags ? local.common_tags : {}

  # Actions S3 autorisees aux instances. Partagees entre la politique IAM et la
  # politique de l'endpoint, pour qu'une seule liste fasse foi.
  app_object_actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
  app_list_actions   = ["s3:ListBucket", "s3:GetBucketLocation"]

  # Buckets AWS lus par l'agent SSM. Sans eux, l'endpoint couperait Session
  # Manager, que le projet utilise pour administrer les instances sans port SSH.
  ssm_artifact_buckets = [
    "aws-ssm-${data.aws_region.current.name}",
    "amazon-ssm-${data.aws_region.current.name}",
    "amazon-ssm-packages-${data.aws_region.current.name}",
    "${data.aws_region.current.name}-birdwatcher-prod",
    "aws-ssm-distributor-file-${data.aws_region.current.name}",
    "aws-ssm-document-attachments-${data.aws_region.current.name}",
    "patch-baseline-snapshot-${data.aws_region.current.name}",
  ]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Politique de moindre privilege pour les instances applicatives
#
# Accorde uniquement ce dont l'application Heart Care a besoin :
#   - lecture/ecriture des objets applicatifs dans son bucket S3
#   - lecture des secrets de son arborescence SSM Parameter Store
#   - ecriture de ses propres logs CloudWatch
# Aucun privilege administratif, aucune action sur un autre projet.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "app" {
  # Acces aux objets du bucket applicatif
  statement {
    sid       = "AppBucketObjectAccess"
    effect    = "Allow"
    actions   = local.app_object_actions
    resources = ["${var.app_bucket_arn}/*"]
  }

  # Listage limite au bucket applicatif
  statement {
    sid       = "AppBucketList"
    effect    = "Allow"
    actions   = local.app_list_actions
    resources = [var.app_bucket_arn]
  }

  # Ecriture des logs applicatifs dans le bucket de logs
  statement {
    sid       = "LogsBucketWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.logs_bucket_arn}/*"]
  }

  # Lecture des parametres/secrets du projet uniquement
  statement {
    sid    = "ParameterStoreRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*",
    ]
  }

  # Dechiffrement des SecureString SSM
  statement {
    sid       = "DecryptParameters"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # Logs CloudWatch de l'application
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${local.name_prefix}*",
    ]
  }

  # Enregistrement de l'instance aupres de SSM Session Manager (acces sans SSH)
  statement {
    sid    = "SessionManager"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ssm:UpdateInstanceInformation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app" {
  provider = aws.untagged

  name_prefix = "${local.name_prefix}-app-"
  description = "Politique de moindre privilege des instances applicatives ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.app.json

  tags = local.iam_tags
}

# ---------------------------------------------------------------------------
# Role applicatif
#
# AWS Academy Learner Lab refuse iam:CreateRole et iam:AttachRolePolicy.
# Le code du role est conserve et pilote par var.create_iam_role : il
# s'applique tel quel sur un compte AWS standard (create_iam_role = true),
# et reste desactive dans le Learner Lab, ou l'on reutilise le role
# pre-provisionne du lab (var.existing_role_name).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  provider = aws.untagged
  count    = var.create_iam_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-app-"
  description          = "Role des instances applicatives ${var.project_name} (${var.environment})"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = local.iam_tags
}

resource "aws_iam_role_policy_attachment" "app" {
  provider = aws.untagged
  count    = var.create_iam_role ? 1 : 0

  role       = aws_iam_role.app[0].name
  policy_arn = aws_iam_policy.app.arn
}

# Role existant du lab, utilise quand create_iam_role = false
data "aws_iam_role" "existing" {
  provider = aws.untagged
  count    = var.create_iam_role ? 0 : 1
  name     = var.existing_role_name
}

# ---------------------------------------------------------------------------
# Instance profile
#
# Cree par Terraform dans les deux cas (iam:CreateInstanceProfile et
# iam:AddRoleToInstanceProfile sont autorises dans le Learner Lab).
# ---------------------------------------------------------------------------
resource "aws_iam_instance_profile" "app" {
  provider = aws.untagged

  name_prefix = "${local.name_prefix}-app-"
  role        = var.create_iam_role ? aws_iam_role.app[0].name : data.aws_iam_role.existing[0].name

  tags = local.iam_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Moindre privilege applique reellement sur S3, par le reseau
#
# AWS Academy Learner Lab refuse les quatre moyens de lier une politique a un
# role (CreateRole, AttachRolePolicy, PutRolePolicy, PutRolePermissionsBoundary).
# Les instances portent donc LabRole, dont les permissions sont tres larges, et
# la politique ci-dessus n'est jamais appliquee.
#
# Un endpoint de passerelle S3 porte sa propre politique, evaluee EN PLUS des
# permissions IAM : une requete doit etre permise par les deux. Les instances
# n'ont pas d'adresse publique, leur seul chemin vers S3 passe par cet endpoint
# (la route du prefixe S3 est plus specifique que la route par defaut vers la
# NAT). Meme avec LabRole, elles ne peuvent donc toucher que les deux buckets du
# projet, et seulement avec les actions de local.app_*_actions.
#
# Portee : S3 uniquement. SSM, CloudWatch et les autres services restent regis
# par LabRole. Gratuit, et economise en plus le trafic S3 facture par la NAT.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    sid       = "AppBucketObjectAccess"
    effect    = "Allow"
    actions   = local.app_object_actions
    resources = ["${var.app_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "AppBucketList"
    effect    = "Allow"
    actions   = local.app_list_actions
    resources = [var.app_bucket_arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "LogsBucketWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.logs_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid       = "SsmAgentArtifacts"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [for b in local.ssm_artifact_buckets : "arn:aws:s3:::${b}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.vpc_id == "" ? 0 : 1

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
  policy            = data.aws_iam_policy_document.s3_endpoint.json

  tags = merge(
    local.common_tags,
    { Name = "${local.name_prefix}-s3-endpoint" }
  )
}
