import json
import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger            = Logger(service="sfn-starter")
sfn_client        = boto3.client("stepfunctions")
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]


@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:
    """Triggered by SNS when Textract completes — starts the processing Step Functions execution."""
    sns_message  = json.loads(event["Records"][0]["Sns"]["Message"])
    job_id       = sns_message["JobId"]
    status       = sns_message["Status"]
    doc_location = sns_message.get("DocumentLocation", {})
    bucket       = doc_location.get("S3Bucket", "")
    key          = doc_location.get("S3ObjectName", "")

    logger.info("Textract completion received", extra={"job_id": job_id, "status": status, "key": key})

    if status == "FAILED":
        logger.error("Textract job failed — skipping Step Functions", extra={"job_id": job_id})
        return {"statusCode": 200, "body": json.dumps({"skipped": True, "reason": "Textract FAILED"})}

    response      = sfn_client.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=json.dumps({"job_id": job_id, "bucket": bucket, "key": key}),
    )
    execution_arn = response["executionArn"]
    logger.info("Step Functions execution started", extra={"execution_arn": execution_arn, "job_id": job_id})

    return {"statusCode": 200, "body": json.dumps({"execution_arn": execution_arn})}
