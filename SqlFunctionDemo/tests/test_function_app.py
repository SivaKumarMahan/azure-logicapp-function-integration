"""Tests for the HTTP handler. The database layer (db.py) is mocked."""

import json
from unittest import mock

import azure.functions as func
import pytest

import db
import function_app

handler = function_app.process_file.build().get_user_function()


def make_request(body) -> func.HttpRequest:
    raw = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
    return func.HttpRequest(
        method="POST",
        url="/api/processfile",
        headers={"Content-Type": "application/json"},
        body=raw,
    )


@pytest.fixture
def insert():
    with mock.patch.object(db, "insert_processed_file", return_value=42) as m:
        yield m


def test_valid_request_inserts_row_and_returns_201(insert):
    resp = handler(make_request({"fileName": " orders.csv ", "content": "a,b\n1,2"}))

    assert resp.status_code == 201
    assert resp.mimetype == "application/json"
    assert json.loads(resp.get_body()) == {"id": 42, "fileName": "orders.csv", "status": "Processed"}
    insert.assert_called_once_with("orders.csv", "a,b\n1,2")


def test_empty_content_is_allowed(insert):
    resp = handler(make_request({"fileName": "empty.txt", "content": ""}))
    assert resp.status_code == 201


def test_invalid_json_returns_400(insert):
    resp = handler(make_request(b"{not json"))
    assert resp.status_code == 400
    insert.assert_not_called()


@pytest.mark.parametrize(
    "body",
    [
        [],
        "just a string",
        {},
        {"content": "x"},
        {"fileName": "", "content": "x"},
        {"fileName": "   ", "content": "x"},
        {"fileName": 123, "content": "x"},
        {"fileName": "a.txt"},
        {"fileName": "a.txt", "content": None},
        {"fileName": "a.txt", "content": {"nested": True}},
        {"fileName": "x" * 256, "content": "x"},
        {"fileName": "bad\nname.txt", "content": "x"},
    ],
)
def test_invalid_payload_returns_400(insert, body):
    resp = handler(make_request(body))
    assert resp.status_code == 400
    assert "error" in json.loads(resp.get_body())
    insert.assert_not_called()


def test_content_too_large_returns_400(insert):
    big = "x" * (function_app.MAX_CONTENT_BYTES + 1)
    resp = handler(make_request({"fileName": "big.txt", "content": big}))
    assert resp.status_code == 400
    insert.assert_not_called()


def test_sql_injection_text_is_passed_as_data(insert):
    evil = "x'); DROP TABLE ProcessedFiles;--"
    resp = handler(make_request({"fileName": evil, "content": evil}))
    assert resp.status_code == 201
    insert.assert_called_once_with(evil, evil)


def test_database_error_returns_generic_500(caplog):
    secret_detail = "Login failed for user 'sqladmin' on server secret-server"
    with mock.patch.object(db, "insert_processed_file", side_effect=RuntimeError(secret_detail)):
        resp = handler(make_request({"fileName": "a.txt", "content": "x"}))

    assert resp.status_code == 500
    body = resp.get_body().decode()
    assert secret_detail not in body
    assert json.loads(body) == {"error": "Failed to process file"}
    # The detail is still logged (with traceback) for Application Insights.
    assert secret_detail in caplog.text


def test_missing_configuration_returns_500():
    with mock.patch.object(db, "insert_processed_file", side_effect=db.ConfigError("missing")):
        resp = handler(make_request({"fileName": "a.txt", "content": "x"}))
    assert resp.status_code == 500
    assert json.loads(resp.get_body()) == {"error": "Service is not configured"}
