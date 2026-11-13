output "app_policy_arn" {
  value       = aws_iam_policy.app.arn
  description = "ARN of the least-privilege application policy"
}

output "app_policy_name" {
  value       = aws_iam_policy.app.name
  description = "Name of the least-privilege application policy"
}

output "app_role_name" {
  value       = var.create_iam_role ? aws_iam_role.app[0].name : data.aws_iam_role.existing[0].name
  description = "Name of the role bound to the application instance profile"
}

output "app_role_arn" {
  value       = var.create_iam_role ? aws_iam_role.app[0].arn : data.aws_iam_role.existing[0].arn
  description = "ARN of the role bound to the application instance profile"
}

output "app_instance_profile_name" {
  value       = aws_iam_instance_profile.app.name
  description = "Name of the Terraform-managed instance profile attached to the app instances"
}

output "app_instance_profile_arn" {
  value       = aws_iam_instance_profile.app.arn
  description = "ARN of the Terraform-managed instance profile"
}

output "policy_attached_to_role" {
  value       = var.create_iam_role
  description = "Whether the least-privilege policy is attached to the role. False on Learner Lab, where iam:AttachRolePolicy is denied: the policy is created but the lab role's own permissions apply at runtime."
}
