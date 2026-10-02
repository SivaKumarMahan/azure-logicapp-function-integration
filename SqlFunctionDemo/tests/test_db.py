"""Tests for db.py. pyodbc and azure.identity are replaced with fakes."""

import struct
import sys
import types
from unittest import mock

import pytest

import db

CONN_STR = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:example.database.windows.net,1433;Database=demo;"


@pytest.fixture
def fake_pyodbc(monkeypatch):
    module = types.ModuleType("pyodbc")
    conn = mock.MagicMock(name="connection")
    cursor = conn.cursor.return_value
    cursor.fetchone.return_value = (7,)
    module.connect = mock.MagicMock(return_value=conn)
    monkeypatch.setitem(sys.modules, "pyodbc", module)
    return module


@pytest.fixture
def fake_identity(monkeypatch):
    identity = types.ModuleType("azure.identity")
    credential = mock.MagicMock()
    credential.get_token.return_value = types.SimpleNamespace(token="abc")
    identity.DefaultAzureCredential = mock.MagicMock(return_value=credential)
    monkeypatch.setitem(sys.modules, "azure.identity", identity)
    return identity


def test_missing_connection_string_raises_config_error(monkeypatch, fake_pyodbc):
    monkeypatch.delenv("SQL_CONNECTION_STRING", raising=False)
    with pytest.raises(db.ConfigError):
        db.get_connection()
    fake_pyodbc.connect.assert_not_called()


def test_connection_string_auth(monkeypatch, fake_pyodbc):
    monkeypatch.setenv("SQL_CONNECTION_STRING", CONN_STR)
    monkeypatch.setenv("SQL_USE_MANAGED_IDENTITY", "false")

    db.get_connection()

    fake_pyodbc.connect.assert_called_once_with(CONN_STR, timeout=30)


def test_managed_identity_passes_access_token(monkeypatch, fake_pyodbc, fake_identity):
    monkeypatch.setenv("SQL_CONNECTION_STRING", CONN_STR)
    monkeypatch.setenv("SQL_USE_MANAGED_IDENTITY", "True")

    db.get_connection()

    fake_identity.DefaultAzureCredential.return_value.get_token.assert_called_once_with(db.SQL_TOKEN_SCOPE)
    args, kwargs = fake_pyodbc.connect.call_args
    assert args == (CONN_STR,)
    token = kwargs["attrs_before"][db.SQL_COPT_SS_ACCESS_TOKEN]
    encoded = "abc".encode("utf-16-le")
    assert token == struct.pack(f"<I{len(encoded)}s", len(encoded), encoded)


def test_insert_uses_parameters_and_commits(monkeypatch, fake_pyodbc):
    monkeypatch.setenv("SQL_CONNECTION_STRING", CONN_STR)
    conn = fake_pyodbc.connect.return_value
    cursor = conn.cursor.return_value

    new_id = db.insert_processed_file("a'; DROP TABLE x;--", "body")

    assert new_id == 7
    sql, *params = cursor.execute.call_args.args
    assert sql == db.INSERT_SQL
    assert sql.count("?") == 3
    assert "DROP" not in sql
    assert params == ["a'; DROP TABLE x;--", "Processed", "body"]
    conn.commit.assert_called_once()
    cursor.close.assert_called_once()
    conn.close.assert_called_once()


def test_insert_rolls_back_and_closes_on_error(monkeypatch, fake_pyodbc):
    monkeypatch.setenv("SQL_CONNECTION_STRING", CONN_STR)
    conn = fake_pyodbc.connect.return_value
    conn.cursor.return_value.execute.side_effect = RuntimeError("boom")

    with pytest.raises(RuntimeError):
        db.insert_processed_file("a.txt", "body")

    conn.rollback.assert_called_once()
    conn.commit.assert_not_called()
    conn.close.assert_called_once()
