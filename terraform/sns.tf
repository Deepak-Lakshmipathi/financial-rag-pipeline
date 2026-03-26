# SNS topic — Textract publishes here when a job completes
resource "aws_sns_topic" "textract_complete" {
  name = "textract-job-complete"
}

# IAM role that Textract assumes to publish to SNS
resource "aws_iam_role" "textract_sns_role" {
  name = "financial-rag-textract-sns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "textract.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "textract_sns_publish" {
  name = "textract-sns-publish"
  role = aws_iam_role.textract_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.textract_complete.arn
    }]
  })
}

# Wire SNS → textract_complete Lambda
resource "aws_sns_topic_subscription" "textract_to_lambda" {
  topic_arn = aws_sns_topic.textract_complete.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.textract_complete.arn
}

resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_complete.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.textract_complete.arn
}

output "textract_sns_topic_arn" { value = aws_sns_topic.textract_complete.arn }
output "textract_sns_role_arn"  { value = aws_iam_role.textract_sns_role.arn }