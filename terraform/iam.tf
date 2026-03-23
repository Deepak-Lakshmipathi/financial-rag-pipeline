resource "aws_iam_role" "lambda_execution" {
  name = "prog1-finrag-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_permissions" {
  name        = "prog1-finrag-lambda-permissions"
  description = "Least-privilege permissions for the RAG ingestion Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ReadRaw"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.financial_docs.arn}/raw/*"
      },
      {
        Sid    = "S3WriteProcessed"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.financial_docs.arn}/processed/*",
          "${aws_s3_bucket.financial_docs.arn}/chunks/*"
        ]
      },
      {
        # Textract does not support resource-level IAM permissions.
        # Resource: * is explicitly required — documented at:
        # https://docs.aws.amazon.com/textract/latest/dg/security_iam_service-with-iam.html
        Sid    = "TextractAsync"
        Effect = "Allow"
        Action = [
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-ingestion-lambda"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}