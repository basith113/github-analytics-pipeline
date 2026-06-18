"""Create the Snowflake foundation objects required by the pipeline."""

from __future__ import annotations

import os
import re

from dotenv import load_dotenv
import snowflake.connector


load_dotenv()


def _identifier(name: str, default: str | None = None) -> str:
    value = (name or default or "").strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", value):
        raise ValueError(f"Invalid Snowflake identifier: {value!r}")
    return value.upper()


def main() -> int:
    database = _identifier(os.getenv("SNOWFLAKE_DATABASE"), "GITHUB_DBT")
    warehouse = _identifier(os.getenv("SNOWFLAKE_WAREHOUSE"), "COMPUTE_WH")
    role = os.getenv("SNOWFLAKE_ROLE")

    required = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD"]
    missing = [key for key in required if not os.getenv(key)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

    conn = snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=os.getenv("SNOWFLAKE_USER"),
        password=os.getenv("SNOWFLAKE_PASSWORD"),
        warehouse=warehouse,
        role=role,
    )

    statements = [
        f"USE WAREHOUSE {warehouse}",
        f"CREATE DATABASE IF NOT EXISTS {database}",
        f"CREATE SCHEMA IF NOT EXISTS {database}.RAW",
        f"CREATE SCHEMA IF NOT EXISTS {database}.STAGING",
        f"CREATE SCHEMA IF NOT EXISTS {database}.MARTS",
        f"""
        CREATE TABLE IF NOT EXISTS {database}.RAW.GITHUB_EVENTS (
            RAW_DATA VARIANT NOT NULL,
            FILE_NAME VARCHAR(50) NOT NULL,
            LOAD_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            _INSERTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            _FILE_ROW_NUMBER INT
        )
        """,
        f"""
        CREATE TABLE IF NOT EXISTS {database}.RAW.LOAD_HISTORY (
            FILE_NAME VARCHAR(50) NOT NULL,
            LOAD_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            FILE_HOUR TIMESTAMP_NTZ NOT NULL,
            ROW_COUNT INT NOT NULL,
            FILE_SIZE_BYTES INT,
            STATUS VARCHAR(20) NOT NULL,
            ERROR_MESSAGE VARCHAR(1000),
            RETRY_COUNT INT DEFAULT 0,
            LOAD_DURATION_SECONDS DECIMAL(10,2),
            PROCESSING_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            LOADED_BY VARCHAR(255),
            PRIMARY KEY (FILE_NAME)
        )
        """,
    ]

    try:
        cursor = conn.cursor()
        for statement in statements:
            cursor.execute(statement)

        for table in ["GITHUB_EVENTS", "LOAD_HISTORY"]:
            cursor.execute(f"SELECT COUNT(*) FROM {database}.RAW.{table}")
            count = cursor.fetchone()[0]
            print(f"{database}.RAW.{table}: {count} rows")
    finally:
        cursor.close()
        conn.close()

    print("Snowflake foundation bootstrap complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
