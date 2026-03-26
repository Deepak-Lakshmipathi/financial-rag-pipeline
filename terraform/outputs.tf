output "docs_bucket_name" {
  description = "Name of the financial documents S3 bucket"
  value       = aws_s3_bucket.financial_docs.bucket
}

output "docs_bucket_arn" {
  description = "ARN of the financial documents S3 bucket"
  value       = aws_s3_bucket.financial_docs.arn
}

output "textract_submitter_lambda_arn" {
  description = "ARN of the Textract submitter Lambda"
  value       = aws_lambda_function.textract_submitter.arn
}

output "sfn_starter_lambda_arn" {
  description = "ARN of the Step Functions starter Lambda"
  value       = aws_lambda_function.sfn_starter.arn
}

output "pipeline_lambda_arn" {
  description = "ARN of the pipeline processing Lambda"
  value       = aws_lambda_function.pipeline.arn
}

output "state_machine_arn" {
  description = "ARN of the financial RAG processing state machine"
  value       = aws_sfn_state_machine.pipeline.arn
}
