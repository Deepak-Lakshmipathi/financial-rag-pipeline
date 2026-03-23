
resource "aws_cloudwatch_log_group" "ingestion_lambda" {
  name = "/aws/lambda/prog1-finrag-ingestion-lambda"
  retention_in_days = 30
}