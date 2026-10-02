"""Database layer for the ProcessFile function.

Kept separate from function_app.py so the HTTP handler can be unit tested
with this module mocked, and so pyodbc (which needs the native unixODBC
library) is only imported when a real connection is opened.

Connection settings (app settings / environment variables):

- SQL_CONNECTION_STRING      ODBC connection string. In Azure this is a
                             Key Vault reference, never a literal value.
- SQL_USE_MANAGED_IDENTITY   "true" to authenticate with an Entra ID access
                             token from DefaultAzureCredential (managed
                             identity in Azure, `az login` locally). The
                             connection string must then NOT contain
                             UID/PWD or Authentication=.
"""

from __future__ import annotations

import os
import struct
from contextlib import closing

# Connection attribute used by the Microsoft ODBC driver to accept an
# Entra ID access token (msodbcsql.h: SQL_COPT_SS_ACCESS_TOKEN).
SQL_COPT_SS_ACCESS_TOKEN = 1256
SQL_TOKEN_SCOPE = "https://database.windows.net/.default"

INSERT_SQL = (
    "INSERT INTO dbo.ProcessedFiles (FileName, ProcessedTime, Status, Content) "
    "OUTPUT INSERTED.Id "
    "VALUES (?, SYSUTCDATETIME(), ?, ?);"
)


class ConfigError(RuntimeError):
    """Raised when required app settings are missing."""


def _use_managed_identity() -> bool:
    return os.environ.get("SQL_USE_MANAGED_IDENTITY", "false").strip().lower() in (
        "1",
        "true",
        "yes",
    )


def _access_token_struct() -> bytes:
    """Return an Entra ID token in the format the ODBC driver expects."""
    from azure.identity import DefaultAzureCredential  # imported lazily

    token = DefaultAzureCredential().get_token(SQL_TOKEN_SCOPE).token
    token_bytes = token.encode("utf-16-le")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


def get_connection():
    """Open a new pyodbc connection using the configured auth mode."""
    conn_str = os.environ.get("SQL_CONNECTION_STRING", "").strip()
    if not conn_str:
        raise ConfigError("SQL_CONNECTION_STRING app setting is not set")

    import pyodbc  # imported lazily: needs the native ODBC driver

    if _use_managed_identity():
        return pyodbc.connect(
            conn_str,
            attrs_before={SQL_COPT_SS_ACCESS_TOKEN: _access_token_struct()},
            timeout=30,
        )
    return pyodbc.connect(conn_str, timeout=30)


def insert_processed_file(file_name: str, content: str, status: str = "Processed") -> int:
    """Insert one row with a parameterized query and return the new Id.

    The connection and cursor are always closed, and the transaction is
    rolled back if the insert fails.
    """
    with closing(get_connection()) as conn:
        try:
            with closing(conn.cursor()) as cursor:
                cursor.execute(INSERT_SQL, file_name, status, content)
                row = cursor.fetchone()
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return int(row[0])
