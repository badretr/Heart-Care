output "bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Name of the Terraform state bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "ARN of the Terraform state bucket"
}

output "bucket_region" {
  value       = aws_s3_bucket.terraform_state.region
  description = "Region of the Terraform state bucket"
}

output "dynamodb_table_name" {
  value       = var.enable_lock_table ? aws_dynamodb_table.terraform_lock[0].name : null
  description = "Name of the DynamoDB lock table"
}

output "backend_config_dev" {
  value = var.enable_lock_table ? (<<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "dev/terraform.tfstate"
    region         = "${var.aws_region}"
    encrypt        = true
    dynamodb_table = "${aws_dynamodb_table.terraform_lock[0].name}"
  EOT
    ) : (<<-EOT
    bucket = "${aws_s3_bucket.terraform_state.id}"
    key    = "dev/terraform.tfstate"
    region = "${var.aws_region}"
    encrypt = true
  EOT
  )
  description = "Backend config for dev environment"
}

output "backend_config_test" {
  value = var.enable_lock_table ? (<<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "test/terraform.tfstate"
    region         = "${var.aws_region}"
    encrypt        = true
    dynamodb_table = "${aws_dynamodb_table.terraform_lock[0].name}"
  EOT
    ) : (<<-EOT
    bucket = "${aws_s3_bucket.terraform_state.id}"
    key    = "test/terraform.tfstate"
    region = "${var.aws_region}"
    encrypt = true
  EOT
  )
  description = "Backend config for test environment"
}

output "backend_config_prod" {
  value = var.enable_lock_table ? (<<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "prod/terraform.tfstate"
    region         = "${var.aws_region}"
    encrypt        = true
    dynamodb_table = "${aws_dynamodb_table.terraform_lock[0].name}"
  EOT
    ) : (<<-EOT
    bucket = "${aws_s3_bucket.terraform_state.id}"
    key    = "prod/terraform.tfstate"
    region = "${var.aws_region}"
    encrypt = true
  EOT
  )
  description = "Backend config for prod environment"
}

output "init_command_dev" {
  value       = var.enable_lock_table ? "terraform init -backend-config=bucket=${aws_s3_bucket.terraform_state.id} -backend-config=key=dev/terraform.tfstate -backend-config=region=${var.aws_region} -backend-config=encrypt=true -backend-config=dynamodb_table=${aws_dynamodb_table.terraform_lock[0].name}" : "terraform init -backend-config=bucket=${aws_s3_bucket.terraform_state.id} -backend-config=key=dev/terraform.tfstate -backend-config=region=${var.aws_region} -backend-config=encrypt=true"
  description = "Terraform init command for dev"
}
