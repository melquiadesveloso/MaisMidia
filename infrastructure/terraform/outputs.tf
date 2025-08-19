output "api_gateway_url" {
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.deploy.stage_name}"
  description = "API base URL"
}

output "cloudfront_url" {
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
  description = "CloudFront URL"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.media_bucket.bucket
  description = "S3 bucket name"
}

