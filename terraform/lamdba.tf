# zip lambda src files
data "archive_file" "ingestion_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../src/ingestion"
  output_path = "${path.module}/../dist/ingestion.zip"
  excludes    = ["requirements.txt", "__pycache__"]
}

# Install Python dependencies into dist/layer/python so Lambda can find them
resource "null_resource" "ingestion_layer_build" {
  triggers = {
    requirements = filesha256("${path.module}/../src/ingestion/requirements.txt")
  }

  provisioner "local-exec" {
    command = "pip install -r ${path.module}/../src/ingestion/requirements.txt -t ${path.module}/../dist/layer/python --quiet"
  }
}

# the archive file that has all the deps
data "archive_file" "ingestion_layer" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/layer"
  output_path = "${path.module}/../dist/ingestion-layer.zip"

  depends_on = [null_resource.ingestion_layer_build]
}

# lambda layer
resource "aws_lambda_layer_version" "ingestion_deps" {
  layer_name          = "prog1-finrag-ingestion-deps"
  filename            = data.archive_file.ingestion_layer.output_path
  source_code_hash    = data.archive_file.ingestion_layer.output_base64sha256
  compatible_runtimes = ["python3.11"]
}

# gateway lambda - triggered by S3 file drop
resource "aws_lambda_function" "ingestion" {
  function_name    = "prog1-finrag-ingestion-lambda"
  filename         = data.archive_file.ingestion_lambda.output_path
  source_code_hash = data.archive_file.ingestion_lambda.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_execution.arn
  timeout          = 600
  memory_size      = 512
  layers           = [aws_lambda_layer_version.ingestion_deps.arn]

  environment {
    variables = {
      LOG_LEVEL               = "INFO"
      POWERTOOLS_SERVICE_NAME = "ingestion"
      POWERTOOLS_LOG_LEVEL    = "INFO"
      STATE_MACHINE_ARN       = local.sfn_ingestion_arn
      DOCS_BUCKET             = aws_s3_bucket.financial_docs.id
    }
  }

  tags = { project = "prog1-finrag" }
}

# Allow S3 to invoke this Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.financial_docs.arn
}

# S3 event trigger — fires on any PUT to raw/ prefix
resource "aws_s3_bucket_notification" "ingestion_trigger" {
  bucket = aws_s3_bucket.financial_docs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }

  # triggr must deploy after permissions
  depends_on = [aws_lambda_permission.allow_s3]
}