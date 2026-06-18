#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
DAG_ID="${DAG_ID:-github_analytics_pipeline}"
AIRFLOW_CONTAINER="${AIRFLOW_CONTAINER:-github-airflow}"
SKIP_BACKFILL="${SKIP_BACKFILL:-0}"
SKIP_DBT="${SKIP_DBT:-0}"
SKIP_AIRFLOW="${SKIP_AIRFLOW:-0}"
TRIGGER_INITIAL_DAG_RUN="${TRIGGER_INITIAL_DAG_RUN:-1}"
RESTART_AIRFLOW_CONTAINER="${RESTART_AIRFLOW_CONTAINER:-1}"

log() {
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

find_python() {
  if [[ -n "${BOOTSTRAP_PYTHON_BIN:-}" ]]; then
    printf '%s\n' "$BOOTSTRAP_PYTHON_BIN"
  elif [[ -x "$ROOT_DIR/.venv/Scripts/python.exe" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/Scripts/python.exe"
  elif [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/bin/python"
  elif command -v python >/dev/null 2>&1; then
    command -v python
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    die "Python was not found. Install Python or set BOOTSTRAP_PYTHON_BIN."
  fi
}

find_dbt() {
  if [[ -n "${BOOTSTRAP_DBT_BIN:-}" ]]; then
    printf '%s\n' "$BOOTSTRAP_DBT_BIN"
  elif command -v dbt >/dev/null 2>&1; then
    command -v dbt
  elif [[ -x "$ROOT_DIR/.venv/Scripts/dbt.exe" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/Scripts/dbt.exe"
  elif [[ -x "$ROOT_DIR/.venv/bin/dbt" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/bin/dbt"
  else
    die "dbt was not found. Install requirements or set BOOTSTRAP_DBT_BIN."
  fi
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Missing env file: $ENV_FILE"

  local exports
  exports="$("$PYTHON_BIN" - "$ENV_FILE" <<'PY'
import re
import shlex
import sys

try:
    from dotenv import dotenv_values
except ImportError:
    print("python-dotenv is required. Run: pip install -r requirements.txt", file=sys.stderr)
    raise SystemExit(1)

for key, value in dotenv_values(sys.argv[1]).items():
    if value is None:
        continue
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        print(f"Invalid environment variable name in .env: {key}", file=sys.stderr)
        raise SystemExit(1)
    print(f"export {key}={shlex.quote(value)}")
PY
)" || die "Could not parse env file: $ENV_FILE"

  eval "$exports"
}

require_env() {
  local missing=()
  local required=(
    SNOWFLAKE_ACCOUNT
    SNOWFLAKE_USER
    SNOWFLAKE_PASSWORD
    SNOWFLAKE_WAREHOUSE
    SNOWFLAKE_DATABASE
    SNOWFLAKE_SCHEMA
    SNOWFLAKE_ROLE
  )

  for key in "${required[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("$key")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Missing required .env values: ${missing[*]}"
  fi

  if [[ "${SNOWFLAKE_SCHEMA^^}" != "RAW" ]]; then
    die "Set SNOWFLAKE_SCHEMA=RAW. This pipeline loads raw events into the RAW schema."
  fi
}

wait_for_airflow_container() {
  local attempt

  for attempt in {1..60}; do
    if docker exec "$AIRFLOW_CONTAINER" airflow dags list >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

enable_airflow_dag() {
  if [[ "$SKIP_AIRFLOW" == "1" ]]; then
    log "Skipping Airflow setup because SKIP_AIRFLOW=1"
    return
  fi

  if command -v docker >/dev/null 2>&1 \
    && docker ps -a --format '{{.Names}}' | grep -Fxq "$AIRFLOW_CONTAINER"; then
    if [[ "$RESTART_AIRFLOW_CONTAINER" == "1" ]]; then
      log "Restarting Airflow container so the DAG rereads .env"
      docker restart "$AIRFLOW_CONTAINER" >/dev/null
    fi

    log "Waiting for Airflow CLI inside container: $AIRFLOW_CONTAINER"
    wait_for_airflow_container || die "Airflow container exists, but the CLI did not become ready."

    log "Unpausing hourly Airflow DAG: $DAG_ID"
    docker exec "$AIRFLOW_CONTAINER" airflow dags unpause "$DAG_ID"
    docker exec "$AIRFLOW_CONTAINER" airflow dags list | grep -F "$DAG_ID" >/dev/null \
      || die "Airflow cannot see DAG: $DAG_ID"

    if [[ "$TRIGGER_INITIAL_DAG_RUN" == "1" ]]; then
      log "Triggering one immediate DAG run. The schedule will continue hourly after this."
      docker exec "$AIRFLOW_CONTAINER" airflow dags trigger "$DAG_ID"
    fi

    return
  fi

  if command -v airflow >/dev/null 2>&1; then
    log "Unpausing hourly Airflow DAG with local airflow CLI: $DAG_ID"
    airflow dags unpause "$DAG_ID"
    airflow dags list | grep -F "$DAG_ID" >/dev/null \
      || die "Airflow cannot see DAG: $DAG_ID"

    if [[ "$TRIGGER_INITIAL_DAG_RUN" == "1" ]]; then
      log "Triggering one immediate DAG run. The schedule will continue hourly after this."
      airflow dags trigger "$DAG_ID"
    fi

    return
  fi

  die "Airflow was not found. Start Airflow, then rerun with SKIP_BACKFILL=1 SKIP_DBT=1."
}

run_dbt() {
  if [[ "$SKIP_DBT" == "1" ]]; then
    log "Skipping dbt run because SKIP_DBT=1"
    return
  fi

  log "Installing dbt dependencies if needed"
  (
    cd "$ROOT_DIR/dbt/github_dbt"
    if [[ -d dbt_packages/dbt_utils ]]; then
      printf 'dbt_utils already installed\n'
    else
      "$DBT_BIN" deps --profiles-dir "$ROOT_DIR/dbt"
    fi
  )

  log "Running dbt staging and marts"
  (
    cd "$ROOT_DIR/dbt/github_dbt"
    "$DBT_BIN" run --profiles-dir "$ROOT_DIR/dbt" --select tag:staging tag:marts
  )

  log "Running dbt tests"
  (
    cd "$ROOT_DIR/dbt/github_dbt"
    "$DBT_BIN" test --profiles-dir "$ROOT_DIR/dbt" --select tag:staging tag:marts source:github_archive+
  )

  log "Running dbt source freshness"
  (
    cd "$ROOT_DIR/dbt/github_dbt"
    "$DBT_BIN" source freshness --profiles-dir "$ROOT_DIR/dbt" --select github_archive
  )
}

cd "$ROOT_DIR"
PYTHON_BIN="$(find_python)"
DBT_BIN="$(find_dbt)"

log "Loading Snowflake configuration from $ENV_FILE"
load_env
require_env

log "Validating Python dependencies"
"$PYTHON_BIN" -c "import dotenv, requests, snowflake.connector" \
  || die "Python dependencies are missing. Run: pip install -r requirements-pipeline.txt"

log "Creating Snowflake foundation objects in the configured account"
"$PYTHON_BIN" scripts/bootstrap_snowflake_foundation.py

if [[ "$SKIP_BACKFILL" == "1" ]]; then
  log "Skipping 7-day backfill because SKIP_BACKFILL=1"
else
  log "Loading rolling 7 days of GH Archive history into Snowflake"
  "$PYTHON_BIN" ingestion/backfill/load_last_7_days.py
fi

run_dbt
enable_airflow_dag

log "New Snowflake setup complete"
log "Airflow DAG $DAG_ID is enabled. It runs every hour at minute 5 and pulls the latest GH Archive file."
