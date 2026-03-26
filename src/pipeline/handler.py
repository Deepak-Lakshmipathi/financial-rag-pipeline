import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

logger          = Logger(service="pipeline")
textract_client = boto3.client("textract")
s3_client       = boto3.client("s3")
DOCS_BUCKET     = os.environ["DOCS_BUCKET"]


def _get_textract_results(payload: dict, _context: LambdaContext) -> dict:
    """Paginates through all Textract LINE blocks and returns the joined raw text."""
    job_id = payload["job_id"]
    logger.info("Fetching Textract results", extra={"job_id": job_id})

    lines, next_token = [], None
    while True:
        kwargs = {"JobId": job_id}
        if next_token:
            kwargs["NextToken"] = next_token
        response   = textract_client.get_document_text_detection(**kwargs)
        lines     += [b["Text"] for b in response["Blocks"] if b["BlockType"] == "LINE"]
        next_token = response.get("NextToken")
        if not next_token:
            break

    raw_text = "\n".join(lines)
    logger.info("Textract results fetched", extra={"job_id": job_id, "line_count": len(lines)})
    return {"raw_text": raw_text, "line_count": len(lines)}


def _store_raw_text(payload: dict, _context: LambdaContext) -> dict:
    """Writes the extracted raw text to S3 under processed/{job_id}.txt."""
    job_id     = payload["job_id"]
    # Step Functions wraps the previous Lambda result under textractOutput.Payload
    raw_text   = payload["textractOutput"]["Payload"]["raw_text"]
    output_key = f"processed/{job_id}.txt"

    s3_client.put_object(
        Bucket=DOCS_BUCKET,
        Key=output_key,
        Body=raw_text.encode("utf-8"),
    )
    logger.info("Raw text stored", extra={"job_id": job_id, "output_key": output_key})
    return {"output_key": output_key}


_DISPATCH = {
    "get_textract_results": _get_textract_results,
    "store_raw_text":       _store_raw_text,
    # "chunk_text":          _chunk_text,   # Day N — LangChain chunking
    # "embed_chunks":        _embed_chunks, # Day N — vector embedding
}


@logger.inject_lambda_context(log_event=False)
def handler(event: dict, context: LambdaContext) -> dict:
    action = event.get("action")
    if not action:
        raise ValueError("Missing 'action' key in event payload")

    handler_fn = _DISPATCH.get(action)
    if handler_fn is None:
        raise ValueError(f"Unknown action: '{action}'")

    logger.info("Pipeline action invoked", extra={"action": action})
    return handler_fn(event, context)
