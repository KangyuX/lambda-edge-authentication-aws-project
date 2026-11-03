output "site_url" {
  description = "Public URL of the app."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "user_pool_id" {
  description = "Users sign up from the hosted sign-in page; admins can also create them here."
  value       = aws_cognito_user_pool.users.id
}

output "auth_function_name" {
  description = "Lambda@Edge logs are in /aws/lambda/us-east-1.<this name>, in the region of the edge that served the request."
  value       = aws_lambda_function.auth.function_name
}

output "auth_function_version" {
  value = aws_lambda_function.auth.version
}
