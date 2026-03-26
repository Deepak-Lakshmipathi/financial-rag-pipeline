import json
import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger           = Logger(service="textract-submitter")
textract_client  = boto3.client("textract")
TEXTRACT_SNS_ARN = os.environ["TEXTRACT_SNS_ARN"]
TEXTRACT_ROLE_ARN = os.environ["TEXTRACT_ROLE_ARN"]


@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:
    """Triggered by S3 PUT to raw/ — submits each document to Textract.
    Textract will publish a completion notification to TEXTRACT_SNS_ARN when done."""
    submitted = []

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]
        size   = record["s3"]["object"]["size"]

        logger.info("Submitting document to Textract", extra={"bucket": bucket, "key": key, "size_bytes": size})

        response = textract_client.start_document_text_detection(
            DocumentLocation={
                "S3Object": {"Bucket": bucket, "Name": key}
            },
            NotificationChannel={
                "SNSTopicArn": TEXTRACT_SNS_ARN,
                "RoleArn":     TEXTRACT_ROLE_ARN,
            },
            JobTag="finrag-ingestion",
        )
        job_id = response["JobId"]
        logger.info("Textract job submitted", extra={"job_id": job_id, "key": key})
        submitted.append({"job_id": job_id, "key": key})

    return {"statusCode": 200, "body": json.dumps({"submitted": submitted})}
