output "s3_bucket_id" {
  value       = aws_s3_bucket.main.id
  description = "S3 bucket ID"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.main.arn
  description = "S3 bucket ARN"
}

output "s3_bucket_regional_domain_name" {
  value       = aws_s3_bucket.main.bucket_regional_domain_name
  description = "S3 bucket regional domain name"
}

output "s3_logs_bucket_id" {
  value       = aws_s3_bucket.logs.id
  description = "S3 logs bucket ID"
}

output "s3_logs_bucket_arn" {
  value       = aws_s3_bucket.logs.arn
  description = "S3 logs bucket ARN"
}
