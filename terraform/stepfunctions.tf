
resource "aws_sfn_state_machine" "ingestion_pipeline" {
  name     = "financial-rag-ingestion"
  role_arn = aws_iam_role.sfn_execution_role.arn
  type     = "STANDARD"

  tracing_configuration { enabled = true }

  definition = jsonencode({
    Comment = "Financial RAG ingestion: Textract → Chunk → Embed → Index"
    StartAt = "StartTextractJob"
    States = {
      StartTextractJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.ingestion.arn
          "Payload.$"  = "$"
        }
        ResultPath = "$.textractResult"
        Next       = "WaitForCompletion"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
      }
      WaitForCompletion = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Comment  = "Pause until SNS delivers Textract completion — Lambda stores token keyed by job_id"
        Parameters = {
          FunctionName = aws_lambda_function.ingestion.arn
          Payload = {
            "action"           = "store_task_token"
            "TaskToken.$"      = "$$.Task.Token"
            "job_id.$"         = "$.textractResult.Payload.job_id"
          }
        }
        ResultPath     = "$.waitResult"
        TimeoutSeconds = 900
        Next           = "CheckTextractStatus"
        Catch = [{
          ErrorEquals = ["States.TaskFailed", "States.Timeout"]
          Next        = "IngestionFailed"
        }]
      }
      CheckTextractStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.ingestion.arn
          "Payload.$"  = "$"
        }
        ResultPath = "$.extractResult"
        Next       = "ChunkText"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "IngestionFailed"
        }]
      }
      ChunkText = {
        Type    = "Pass"
        Comment = "Day 5 — LangChain chunking Lambda goes here"
        Next    = "PipelineComplete"
      }
      PipelineComplete = {
        Type = "Succeed"
      }
      IngestionFailed = {
        Type  = "Fail"
        Cause = "Textract job failed or Lambda error"
      }
    }
  })
}

resource "aws_iam_role" "sfn_execution_role" {
  name = "financial-rag-sfn-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn_execution_policy" {
  name = "sfn-invoke-lambdas"
  role = aws_iam_role.sfn_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.ingestion.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}