import json
import pytest
from unittest.mock import MagicMock
from src.ingestion.handler import handler

def make_s3_event(bucket: str, key: str, size: int = 1024) -> dict:
    return {
        "Records": [{
            "eventTime": "2026-03-07T10:00:00.000Z",
            "s3": {
                "bucket": {"name": bucket},
                "object": {"key": key, "size": size},
            }
        }]
    }

def test_handler_returns_200():
    event = make_s3_event("financial-docs-123456789", "raw/test_10k.pdf")
    result = handler(event, MagicMock())
    assert result["statusCode"] == 200

def test_handler_parses_multiple_records():
    event = {
        "Records": [
            {"eventTime": "2026-03-07T10:00:00.000Z",
             "s3": {"bucket": {"name": "b"}, "object": {"key": "raw/a.pdf", "size": 100}}},
            {"eventTime": "2026-03-07T10:00:01.000Z",
             "s3": {"bucket": {"name": "b"}, "object": {"key": "raw/b.pdf", "size": 200}}},
        ]
    }
    result = handler(event, MagicMock())
    body = json.loads(result["body"])
    assert body["records_processed"] == 2