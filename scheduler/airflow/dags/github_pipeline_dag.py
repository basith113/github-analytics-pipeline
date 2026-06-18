"""
Airflow DAG for the GitHub Analytics Pipeline.

Flow:
  1. Validate required environment variables.
  2. Install dbt package dependencies.
  3. Load the latest GH Archive hourly file into Snowflake RAW.
  4. Run dbt transformations.
  5. Run dbt tests and source freshness checks.

This DAG assumes Airflow runs from the repository checkout, WSL, Docker, or a
worker with the repository mounted. Override paths with environment variables
when Airflow is not launched from this repo.
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.exceptions import AirflowFailException
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - Airflow image should include python-dotenv.
    load_dotenv = None


LOGGER = logging.getLogger(__name__)


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


REPO_ROOT = Path(os.getenv("PIPELINE_REPO_ROOT", _default_repo_root())).resolve()

if load_dotenv is not None:
    # Local Airflow runs read the repo .env so a Snowflake account switch only
    # needs the .env file updated before restarting/reparsing the DAG.
    load_dotenv(REPO_ROOT / ".env", override=True)

PYTHON_BIN = os.getenv("PIPELINE_PYTHON_BIN", sys.executable)
DBT_BIN = os.getenv("DBT_BIN", "dbt")
DBT_PROJECT_DIR = Path(os.getenv("DBT_PROJECT_DIR", REPO_ROOT / "dbt" / "github_dbt")).resolve()
DBT_PROFILES_DIR = Path(os.getenv("DBT_PROFILES_DIR", REPO_ROOT / "dbt")).resolve()

REQUIRED_ENV_VARS = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PASSWORD",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_SCHEMA",
    "SNOWFLAKE_ROLE",
]


def _quote_path(path_value: str | Path) -> str:
    return '"' + str(path_value).replace('"', '\\"') + '"'


def _airflow_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(REPO_ROOT)
    env["DBT_PROFILES_DIR"] = str(DBT_PROFILES_DIR)
    return env


def validate_environment() -> None:
    missing = [key for key in REQUIRED_ENV_VARS if not os.getenv(key)]
    missing_paths = [
        str(path)
        for path in [REPO_ROOT, DBT_PROJECT_DIR, DBT_PROFILES_DIR]
        if not path.exists()
    ]

    if missing or missing_paths:
        details = []
        if missing:
            details.append(f"Missing environment variables: {', '.join(missing)}")
        if missing_paths:
            details.append(f"Missing paths: {', '.join(missing_paths)}")
        raise AirflowFailException("; ".join(details))

    LOGGER.info("Environment validation passed")
    LOGGER.info("Repository root: %s", REPO_ROOT)
    LOGGER.info("dbt project dir: %s", DBT_PROJECT_DIR)
    LOGGER.info("dbt profiles dir: %s", DBT_PROFILES_DIR)


def notify_failure(context: dict) -> None:
    task_instance = context.get("task_instance")
    dag_run = context.get("dag_run")
    exception = context.get("exception")

    LOGGER.error(
        "GitHub analytics pipeline failed. dag_run=%s task=%s exception=%s",
        getattr(dag_run, "run_id", "unknown"),
        getattr(task_instance, "task_id", "unknown"),
        exception,
    )


default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "on_failure_callback": notify_failure,
}


with DAG(
    dag_id="github_analytics_pipeline",
    description="Hourly GH Archive ingestion, dbt transformation, and quality checks",
    default_args=default_args,
    start_date=datetime(2026, 6, 1),
    schedule="5 * * * *",
    catchup=False,
    max_active_runs=1,
    tags=["github", "snowflake", "dbt", "phase-14"],
) as dag:
    start = EmptyOperator(task_id="start")

    validate_env = PythonOperator(
        task_id="validate_environment",
        python_callable=validate_environment,
    )

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=(
            f"cd {_quote_path(DBT_PROJECT_DIR)} && "
            "if [ -d dbt_packages/dbt_utils ]; then "
            "echo 'dbt packages already installed'; "
            "else "
            f"{_quote_path(DBT_BIN)} deps --profiles-dir {_quote_path(DBT_PROFILES_DIR)}; "
            "fi"
        ),
        env=_airflow_env(),
    )

    load_latest_hour = BashOperator(
        task_id="load_latest_hour",
        bash_command=(
            f"cd {_quote_path(REPO_ROOT)} && "
            f"{_quote_path(PYTHON_BIN)} ingestion/incremental/load_latest_hour.py"
        ),
        env=_airflow_env(),
    )

    dbt_run = BashOperator(
        task_id="dbt_run_incremental_models",
        bash_command=(
            f"cd {_quote_path(DBT_PROJECT_DIR)} && "
            f"{_quote_path(DBT_BIN)} run "
            f"--profiles-dir {_quote_path(DBT_PROFILES_DIR)} "
            "--select tag:staging tag:marts"
        ),
        env=_airflow_env(),
    )

    dbt_test = BashOperator(
        task_id="dbt_test_models",
        bash_command=(
            f"cd {_quote_path(DBT_PROJECT_DIR)} && "
            f"{_quote_path(DBT_BIN)} test "
            f"--profiles-dir {_quote_path(DBT_PROFILES_DIR)} "
            "--select tag:staging tag:marts source:github_archive+"
        ),
        env=_airflow_env(),
    )

    dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=(
            f"cd {_quote_path(DBT_PROJECT_DIR)} && "
            f"{_quote_path(DBT_BIN)} source freshness "
            f"--profiles-dir {_quote_path(DBT_PROFILES_DIR)} "
            "--select github_archive"
        ),
        env=_airflow_env(),
    )

    complete = EmptyOperator(task_id="complete")

    start >> validate_env >> dbt_deps >> load_latest_hour >> dbt_run
    dbt_run >> [dbt_test, dbt_source_freshness] >> complete
