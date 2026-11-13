output "alb_arn" {
  value       = aws_lb.main.arn
  description = "ARN of the load balancer"
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS name of the load balancer"
}

output "alb_zone_id" {
  value       = aws_lb.main.zone_id
  description = "Zone ID of the load balancer"
}

output "target_group_arn" {
  value       = aws_lb_target_group.app.arn
  description = "ARN of the target group"
}

output "target_group_name" {
  value       = aws_lb_target_group.app.name
  description = "Name of the target group"
}

output "alb_url" {
  value       = "http://${aws_lb.main.dns_name}"
  description = "URL of the ALB"
}

output "https_enabled" {
  value       = var.certificate_arn != ""
  description = "Indique si le listener HTTPS est actif"
}
