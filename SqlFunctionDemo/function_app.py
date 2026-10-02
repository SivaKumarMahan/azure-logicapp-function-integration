"""HTTP-triggered Azure Function (Python v2 programming model).

The Logic App calls POST /api/processfile with a JSON body:

    {"fileName": "orders.csv", "content": "<file text>"}

The function validates the body and writes one row to dbo.ProcessedFiles
in Azure SQL through db.py (parameterized query, no string building).
"""

import json
import logging

import azure.functions as func

import db

MAX_FILE_NAME_LENGTH = 255  # matches NVARCHAR(255) in sql/schema.sql
MAX_CONTENT_BYTES = 1_000_000  # keep request bodies small; large files belong in Blob

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)
logger = logging.getLogger("ProcessFile")


def _json_response(payload: dict, status_code: int) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload),
        status_code=status_code,
        mimetype="application/json",
    )


def validate_payload(data: object) -> tuple[str, str]:
    """Return (file_name, content) or raise ValueError with a safe message."""
    if not isinstance(data, dict):
        raise ValueError("Request body must be a JSON object")

    file_name = data.get("fileName")
    content = data.get("content")

    if not isinstance(file_name, str) or not file_name.strip():
        raise ValueError("'fileName' is required and must be a non-empty string")
    file_name = file_name.strip()
    if len(file_name) > MAX_FILE_NAME_LENGTH:
        raise ValueError(f"'fileName' must be at most {MAX_FILE_NAME_LENGTH} characters")
    if any(ch in file_name for ch in ("\x00", "\r", "\n")):
        raise ValueError("'fileName' contains invalid characters")

    if not isinstance(content, str):
        raise ValueError("'content' is required and must be a string")
    if len(content.encode("utf-8")) > MAX_CONTENT_BYTES:
        raise ValueError(f"'content' must be at most {MAX_CONTENT_BYTES} bytes")

    return file_name, content


@app.function_name(name="ProcessFile")
@app.route(route="processfile", methods=["POST"])
def process_file(req: func.HttpRequest) -> func.HttpResponse:
    try:
        data = req.get_json()
    except ValueError:
        return _json_response({"error": "Request body must be valid JSON"}, 400)

    try:
        file_name, content = validate_payload(data)
    except ValueError as exc:
        logger.warning("Rejected request: %s", exc)
        return _json_response({"error": str(exc)}, 400)

    logger.info("Processing file %s (%d chars)", file_name, len(content))

    try:
        row_id = db.insert_processed_file(file_name, content)
    except db.ConfigError:
        logger.exception("Function is not configured")
        return _json_response({"error": "Service is not configured"}, 500)
    except Exception:
        # Full details go to Application Insights; the caller gets a generic message.
        logger.exception("Failed to insert %s into ProcessedFiles", file_name)
        return _json_response({"error": "Failed to process file"}, 500)

    logger.info("Inserted %s as ProcessedFiles.Id=%s", file_name, row_id)
    return _json_response({"id": row_id, "fileName": file_name, "status": "Processed"}, 201)
