# ---------------------------------------------------------------------------
# Lambda 1: textract-submitter
# Permissions: submit docs to Textract + pass the SNS notification role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "textract_submitter_role" {
  name = "prog1-finrag-textract-submitter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "textract_submitter_policy" {
  name = "prog1-finrag-textract-submitter-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TextractSubmit"
        Effect = "Allow"
        # Textract does not support resource-level IAM permissions — Resource: * required.
        # https://docs.aws.amazon.com/textract/latest/dg/security_iam_service-with-iam.html
        Action   = ["textract:StartDocumentTextDetection"]
        Resource = "*"
      },
      {
        Sid    = "S3ReadRaw"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.financial_docs.arn}/raw/*"
      },
      {
        Sid    = "PassTextractRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.textract_sns_role.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "textract.amazonaws.com" }
        }
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-textract-submitter",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-textract-submitter:*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "textract_submitter_policy" {
  role       = aws_iam_role.textract_submitter_role.name
  policy_arn = aws_iam_policy.textract_submitter_policy.arn
}


# ---------------------------------------------------------------------------
# Lambda 2: sfn-starter
# Permissions: start the processing Step Functions execution
# ---------------------------------------------------------------------------

resource "aws_iam_role" "sfn_starter_role" {
  name = "prog1-finrag-sfn-starter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sfn_starter_policy" {
  name = "prog1-finrag-sfn-starter-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartPipelineExecution"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = aws_sfn_state_machine.pipeline.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-sfn-starter",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-sfn-starter:*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn_starter_policy" {
  role       = aws_iam_role.sfn_starter_role.name
  policy_arn = aws_iam_policy.sfn_starter_policy.arn
}


# ---------------------------------------------------------------------------
# Lambda 3: pipeline
# Permissions: read Textract results + write processed/chunks/embeddings to S3
# ---------------------------------------------------------------------------

resource "aws_iam_role" "pipeline_role" {
  name = "prog1-finrag-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "pipeline_policy" {
  name = "prog1-finrag-pipeline-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TextractRead"
        Effect   = "Allow"
        Action   = ["textract:GetDocumentTextDetection"]
        Resource = "*"
      },
      {
        Sid    = "S3WriteProcessed"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.financial_docs.arn}/processed/*",
          "${aws_s3_bucket.financial_docs.arn}/chunks/*",
          "${aws_s3_bucket.financial_docs.arn}/embeddings/*",
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-pipeline",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/prog1-finrag-pipeline:*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_policy" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = aws_iam_policy.pipeline_policy.arn
}
