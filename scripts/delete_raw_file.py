"""Delete a partially loaded raw GH Archive file from Snowflake."""

from __future__ import annotations

import os
import re
import sys

from dotenv import load_dotenv
import snowflake.connector


load_dotenv()


def _identifier(value: str, default: str) -> str:
    name = (value or default).strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", name):
        raise ValueError(f"Invalid Snowflake identifier: {name!r}")
    return name.upper()


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python scripts/delete_raw_file.py <file_name>")
        return 2

    file_name = sys.argv[1]
    database = _identifier(os.getenv("SNOWFLAKE_DATABASE"), "GITHUB_DBT")
    warehouse = _identifier(os.getenv("SNOWFLAKE_WAREHOUSE"), "COMPUTE_WH")

    conn = snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=os.getenv("SNOWFLAKE_USER"),
        password=os.getenv("SNOWFLAKE_PASSWORD"),
        warehouse=warehouse,
        database=database,
        schema="RAW",
        role=os.getenv("SNOWFLAKE_ROLE"),
    )

    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM RAW.GITHUB_EVENTS WHERE FILE_NAME = %s", (file_name,))
        deleted_events = cursor.rowcount
        cursor.execute("DELETE FROM RAW.LOAD_HISTORY WHERE FILE_NAME = %s", (file_name,))
        deleted_history = cursor.rowcount
        conn.commit()
    finally:
        cursor.close()
        conn.close()

    print(f"Deleted {deleted_events} events and {deleted_history} load-history rows for {file_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
