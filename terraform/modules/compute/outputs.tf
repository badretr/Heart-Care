output "launch_template_id" {
  value       = aws_launch_template.app.id
  description = "Launch Template ID"
}

output "launch_template_latest_version" {
  value       = aws_launch_template.app.latest_version
  description = "Latest version of Launch Template"
}

output "autoscaling_group_name" {
  value       = aws_autoscaling_group.app.name
  description = "Auto Scaling Group name"
}

output "autoscaling_group_arn" {
  value       = aws_autoscaling_group.app.arn
  description = "Auto Scaling Group ARN"
}

output "autoscaling_group_min_size" {
  value       = aws_autoscaling_group.app.min_size
  description = "Minimum size of Auto Scaling Group"
}

output "autoscaling_group_max_size" {
  value       = aws_autoscaling_group.app.max_size
  description = "Maximum size of Auto Scaling Group"
}

output "autoscaling_group_desired_capacity" {
  value       = aws_autoscaling_group.app.desired_capacity
  description = "Desired capacity of Auto Scaling Group"
}
