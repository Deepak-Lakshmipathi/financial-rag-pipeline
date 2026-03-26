# ---------------------------------------------------------------------------
# Shared Lambda layer — aws-lambda-powertools used by all three functions
# ---------------------------------------------------------------------------

resource "null_resource" "layer_build" {
  triggers = {
    requirements = filesha256("${path.module}/../src/textract_submitter/requirements.txt")
  }

  provisioner "local-exec" {
    command = "pip install -r ${path.module}/../src/textract_submitter/requirements.txt -t ${path.module}/../dist/layer/python --quiet"
  }
}

data "archive_file" "shared_layer" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/layer"
  output_path = "${path.module}/../dist/shared-layer.zip"
  depends_on  = [null_resource.layer_build]
}

resource "aws_lambda_layer_version" "shared_deps" {
  layer_name          = "prog1-finrag-shared-deps"
  filename            = data.archive_file.shared_layer.output_path
  source_code_hash    = data.archive_file.shared_layer.output_base64sha256
  compatible_runtimes = ["python3.11"]
}


# ---------------------------------------------------------------------------
# Lambda 1: textract-submitter — S3 triggered, submits docs to Textract
# ---------------------------------------------------------------------------

data "archive_file" "textract_submitter" {
  type        = "zip"
  source_dir  = "${path.module}/../src/textract_submitter"
  output_path = "${path.module}/../dist/textract_submitter.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

resource "aws_lambda_function" "textract_submitter" {
  function_name    = "prog1-finrag-textract-submitter"
  filename         = data.archive_file.textract_submitter.output_path
  source_code_hash = data.archive_file.textract_submitter.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.textract_submitter_role.arn
  timeout          = 60
  memory_size      = 256
  layers           = [aws_lambda_layer_version.shared_deps.arn]

  environment {
    variables = {
      LOG_LEVEL               = "INFO"
      POWERTOOLS_SERVICE_NAME = "textract-submitter"
      POWERTOOLS_LOG_LEVEL    = "INFO"
      TEXTRACT_SNS_ARN        = aws_sns_topic.textract_complete.arn
      TEXTRACT_ROLE_ARN       = aws_iam_role.textract_sns_role.arn
    }
  }

  tags = { project = "prog1-finrag" }
}

resource "aws_lambda_permission" "allow_s3_textract_submitter" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_submitter.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.financial_docs.arn
}

resource "aws_s3_bucket_notification" "ingestion_trigger" {
  bucket = aws_s3_bucket.financial_docs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.textract_submitter.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }

  depends_on = [aws_lambda_permission.allow_s3_textract_submitter]
}


# ---------------------------------------------------------------------------
# Lambda 2: sfn-starter — SNS triggered, starts the Step Functions pipeline
# ---------------------------------------------------------------------------

data "archive_file" "sfn_starter" {
  type        = "zip"
  source_dir  = "${path.module}/../src/sfn_starter"
  output_path = "${path.module}/../dist/sfn_starter.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

resource "aws_lambda_function" "sfn_starter" {
  function_name    = "prog1-finrag-sfn-starter"
  filename         = data.archive_file.sfn_starter.output_path
  source_code_hash = data.archive_file.sfn_starter.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.sfn_starter_role.arn
  timeout          = 60
  memory_size      = 256
  layers           = [aws_lambda_layer_version.shared_deps.arn]

  environment {
    variables = {
      LOG_LEVEL               = "INFO"
      POWERTOOLS_SERVICE_NAME = "sfn-starter"
      POWERTOOLS_LOG_LEVEL    = "INFO"
      STATE_MACHINE_ARN       = local.sfn_pipeline_arn
    }
  }

  tags = { project = "prog1-finrag" }
}


# ---------------------------------------------------------------------------
# Lambda 3: pipeline — invoked by Step Functions for each processing state
# ---------------------------------------------------------------------------

data "archive_file" "pipeline" {
  type        = "zip"
  source_dir  = "${path.module}/../src/pipeline"
  output_path = "${path.module}/../dist/pipeline.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

resource "aws_lambda_function" "pipeline" {
  function_name    = "prog1-finrag-pipeline"
  filename         = data.archive_file.pipeline.output_path
  source_code_hash = data.archive_file.pipeline.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.pipeline_role.arn
  timeout          = 600
  memory_size      = 512
  layers           = [aws_lambda_layer_version.shared_deps.arn]

  environment {
    variables = {
      LOG_LEVEL               = "INFO"
      POWERTOOLS_SERVICE_NAME = "pipeline"
      POWERTOOLS_LOG_LEVEL    = "INFO"
      DOCS_BUCKET             = aws_s3_bucket.financial_docs.id
    }
  }

  tags = { project = "prog1-finrag" }
}
