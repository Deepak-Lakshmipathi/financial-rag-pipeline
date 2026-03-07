output "docs_bucket_name" {
  description = "Name of the financial documents S3 bucket"
  value       = aws_s3_bucket.financial_docs.bucket
}

output "docs_bucket_arn" {
  description = "ARN of the financial documents S3 bucket"
  value       = aws_s3_bucket.financial_docs.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}