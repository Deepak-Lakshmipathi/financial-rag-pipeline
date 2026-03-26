resource "aws_cloudwatch_log_group" "textract_submitter" {
  name              = "/aws/lambda/prog1-finrag-textract-submitter"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "sfn_starter" {
  name              = "/aws/lambda/prog1-finrag-sfn-starter"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/lambda/prog1-finrag-pipeline"
  retention_in_days = 30
}
