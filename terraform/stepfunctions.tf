resource "aws_sfn_state_machine" "pipeline" {
  name     = "financial-rag-pipeline"
  role_arn = aws_iam_role.sfn_execution_role.arn
  type     = "STANDARD"

  tracing_configuration { enabled = true }

  definition = jsonencode({
    Comment = "Financial RAG pipeline: extract → store → chunk → embed"
    StartAt = "GetTextractResults"
    States = {

      GetTextractResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pipeline.arn
          Payload = {
            "action"   = "get_textract_results"
            "job_id.$" = "$.job_id"
          }
        }
        ResultPath = "$.textractOutput"
        Next       = "StoreRawText"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "PipelineFailed"
        }]
      }

      StoreRawText = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.pipeline.arn
          Payload = {
            "action"           = "store_raw_text"
            "job_id.$"         = "$.job_id"
            "textractOutput.$" = "$.textractOutput"
          }
        }
        ResultPath = "$.storeResult"
        Next       = "ChunkText"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "PipelineFailed"
        }]
      }

      ChunkText = {
        Type    = "Pass"
        Comment = "Placeholder — LangChain chunking Lambda goes here"
        Next    = "EmbedChunks"
      }

      EmbedChunks = {
        Type    = "Pass"
        Comment = "Placeholder — vector embedding Lambda goes here"
        Next    = "PipelineComplete"
      }

      PipelineComplete = {
        Type = "Succeed"
      }

      PipelineFailed = {
        Type  = "Fail"
        Cause = "Pipeline Lambda error"
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
  name = "sfn-invoke-pipeline-lambda"
  role = aws_iam_role.sfn_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.pipeline.arn
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}
