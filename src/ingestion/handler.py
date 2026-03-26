import json
import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger            = Logger(service="ingestion")
textract_client   = boto3.client("textract")
sfn_client        = boto3.client("stepfunctions")
s3_client         = boto3.client("s3")
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
OUTPUT_BUCKET     = os.environ["DOCS_BUCKET"]
TEXTRACT_SNS_ARN  = os.environ["TEXTRACT_SNS_ARN"]
TEXTRACT_ROLE_ARN = os.environ["TEXTRACT_ROLE_ARN"]



# ---------------------------------------------------------------------------
# Sub-handlers
# ---------------------------------------------------------------------------

def _handle_s3_event(event: dict, context: LambdaContext) -> dict:
    """Triggered by an S3 PUT — starts a Step Functions execution per object."""
    logger.info(f"##### Started _handle_s3_event #####")
    executions_started = []

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]
        size   = record["s3"]["object"]["size"]

        logger.info("Document received", extra={"bucket": bucket, "key": key, "size_bytes": size})

        response = sfn_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps({"bucket": bucket, "key": key, "action": "textract_start"}),
        )
        execution_arn = response["executionArn"]
        logger.info("Pipeline execution started", extra={"execution_arn": execution_arn, "key": key})
        executions_started.append(execution_arn)

    return {"statusCode": 200, "body": json.dumps({"executions_started": executions_started})}


def _handle_sns_event(event: dict) -> str:
    logger.info(f"##### Started _handle_sns_event #####")
    """Triggered via SNS — routes to the correct action.
    Textract completion notifications carry no 'action' field, so default to 'textract_complete'."""
    sns_message = json.loads(event["Records"][0]["Sns"]["Message"])
    return sns_message.get("action", "")


def _store_task_token(payload: dict, _context: LambdaContext) -> dict:
    """Store the Step Functions task token keyed by Textract job_id.
    Called by the WaitForCompletion .waitForTaskToken state so that
    _textract_complete can look up the token when SNS fires."""
    job_id     = payload["job_id"]
    task_token = payload["TaskToken"]

    s3_client.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=f"task-tokens/{job_id}.json",
        Body=json.dumps({"task_token": task_token}).encode("utf-8"),
    )
    logger.info("Task token stored", extra={"job_id": job_id})
    return {"stored": True}


def _textract_complete(event: dict, context: LambdaContext) -> dict:
    logger.info(f"##### Started _textract_complete #####")
    """Invoked via SNS when Textract finishes. Fetches results, saves text to S3,
    then calls send_task_success / send_task_failure to resume the paused SFN execution."""
    sns_message = json.loads(event["Records"][0]["Sns"]["Message"])
    job_id      = sns_message["JobId"]
    job_status  = sns_message["Status"]

    logger.info("Textract job notification received", extra={"job_id": job_id, "status": job_status})

    # Retrieve the task token stored by _store_task_token
    token_obj  = s3_client.get_object(Bucket=OUTPUT_BUCKET, Key=f"task-tokens/{job_id}.json")
    task_token = json.loads(token_obj["Body"].read())["task_token"]

    if job_status == "FAILED":
        logger.error("Textract job failed", extra={"job_id": job_id})
        sfn_client.send_task_failure(
            taskToken=task_token,
            error="TextractFailed",
            cause=f"Textract job {job_id} failed",
        )
        return {"statusCode": 200, "body": json.dumps({"job_id": job_id, "status": "FAILED"})}

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
    output_key = f"processed/{job_id}.txt"

    s3_client.put_object(Bucket=OUTPUT_BUCKET, Key=output_key, Body=raw_text.encode("utf-8"))
    logger.info("Text extracted and saved", extra={"job_id": job_id, "output_key": output_key, "line_count": len(lines)})

    result = {"output_key": output_key, "line_count": len(lines)}
    sfn_client.send_task_success(taskToken=task_token, output=json.dumps(result))

    return {"statusCode": 200, "body": json.dumps(result)}

def _textract_start(payload: dict, _context: LambdaContext) -> dict:
    """Submit an S3 document to Textract for async text detection.
    Expects payload keys: 'bucket' and 'key'.
    Textract will publish a completion notification to TEXTRACT_SNS_ARN."""
    bucket = payload["bucket"]
    key    = payload["key"]

    logger.info("Starting Textract job", extra={"bucket": bucket, "key": key})

    response = textract_client.start_document_text_detection(
        DocumentLocation={
            "S3Object": {"Bucket": bucket, "Name": key}
        },
        NotificationChannel={
            "SNSTopicArn": TEXTRACT_SNS_ARN,
            "RoleArn":     TEXTRACT_ROLE_ARN,
        },
    )
    job_id = response["JobId"]
    logger.info("Textract job submitted", extra={"job_id": job_id, "bucket": bucket, "key": key})

    # Return job_id at the top level so Step Functions can reference it as
    # $.textractResult.Payload.job_id in the WaitForCompletion state.
    return {"job_id": job_id}

# ---------------------------------------------------------------------------
# Step Functions dispatch table
# Register new Step Functions actions here — no changes needed in handler().
# Each function receives (payload: dict, context: LambdaContext) -> dict.
# ---------------------------------------------------------------------------
_SFN_DISPATCH: dict = {
    "textract_start":    _textract_start,
    "store_task_token":  _store_task_token,
    "textract_complete": _textract_complete,
    # "chunk_text":        _chunk_text,
    # "embed_chunks":      _embed_chunks,
}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:
    logger.info(f"EVENT : ||{event}||")
    records      = event.get("Records", [])
    event_source = ""
    action       = event.get("action", "")

    if records:
        first        = records[0]
        # S3 uses lowercase "eventSource"; SNS uses title-case "EventSource"
        event_source = first.get("eventSource") or first.get("EventSource", "")

    # --- S3 trigger ---
    if event_source == "aws:s3":
        return _handle_s3_event(event, context)

    # --- SNS trigger ---
    if event_source == "aws:sns":
        action = _handle_sns_event(event)
        # Textract completion notifications carry no "action" key — route directly.
        if not action:
            return _textract_complete(event, context)

    # --- Direct Step Functions invocation or SNS-routed action ---
    # Step Functions passes {"action": "<name>", ...payload...} as the task input.
    if action:
        handler_fn = _SFN_DISPATCH.get(action)
        if handler_fn is None:
            raise ValueError(f"Unknown Step Functions action: '{action}'")
        logger.info("Step Functions direct invocation", extra={"action": action})
        return handler_fn(event, context)

    raise ValueError(f"Unrecognised event shape — no Records and no 'action' key found")