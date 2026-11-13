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
    sid    = "AppBucketObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.app_bucket_arn}/*"]
  }

  # Listage limite au bucket applicatif
  statement {
    sid    = "AppBucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
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
