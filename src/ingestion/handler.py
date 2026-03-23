import json
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger(service="ingestion")
logger.info("Started Handler")

@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:

    for record in event["Records"]:
        print(f"RECORD: {record}")
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]
        size   = record["s3"]["object"]["size"]

        logger.info(
            "Got Document",
            extra={
                "bucket":     bucket,
                "key":        key,
                "size_bytes": size,
                "event_time": record["eventTime"],
            }
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message":           "Triggered lambda",
            "records_processed": len(event["Records"]),
        })
    }