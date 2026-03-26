import json
import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger          = Logger(service="textract-complete")
textract_client = boto3.client("textract")
s3_client       = boto3.client("s3")
OUTPUT_BUCKET   = os.environ["DOCS_BUCKET"]

@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:
    # SNS wraps Textract's notification in a Records array
    sns_message = json.loads(event["Records"][0]["Sns"]["Message"])
    job_id      = sns_message["JobId"]
    job_status  = sns_message["Status"]

    logger.info("Textract job notification received", extra={"job_id": job_id, "status": job_status})

    if job_status == "FAILED":
        logger.error("Textract job failed", extra={"job_id": job_id})
        raise Exception(f"Textract job {job_id} failed — Step Functions will route to error branch")

    # SUCCEEDED — paginate through all result pages
    lines, next_token = [], None
    while True:
        kwargs   = {"JobId": job_id}
        if next_token:
            kwargs["NextToken"] = next_token
        response = textract_client.get_document_text_detection(**kwargs)
        lines   += [b["Text"] for b in response["Blocks"] if b["BlockType"] == "LINE"]
        next_token = response.get("NextToken")
        if not next_token:
            break

    raw_text   = "\n".join(lines)
    # Derive output key from the job_id (Step Functions will pass bucket/key via task token in a later iteration)
    output_key = f"processed/{job_id}.txt"

    s3_client.put_object(Bucket=OUTPUT_BUCKET, Key=output_key, Body=raw_text.encode("utf-8"))
    logger.info("Text extracted and saved", extra={"job_id": job_id, "output_key": output_key, "line_count": len(lines)})

    return {"statusCode": 200, "body": json.dumps({"output_key": output_key, "line_count": len(lines)})}