#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
INSTALL_REQUIREMENTS="${INSTALL_REQUIREMENTS:-1}"
START_AIRFLOW="${START_AIRFLOW:-1}"
RUN_BOOTSTRAP="${RUN_BOOTSTRAP:-1}"

log() {
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

find_system_python() {
  if [[ -n "${SETUP_PYTHON_BIN:-}" ]]; then
    printf '%s\n' "$SETUP_PYTHON_BIN"
  elif command -v python >/dev/null 2>&1; then
    command -v python
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    die "Python was not found. Install Python 3.11+, then rerun this script."
  fi
}

venv_python_path() {
  if [[ -x "$ROOT_DIR/.venv/Scripts/python.exe" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/Scripts/python.exe"
  elif [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/bin/python"
  else
    die "Virtual environment Python was not found."
  fi
}

venv_dbt_path() {
  if [[ -x "$ROOT_DIR/.venv/Scripts/dbt.exe" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/Scripts/dbt.exe"
  elif [[ -x "$ROOT_DIR/.venv/bin/dbt" ]]; then
    printf '%s\n' "$ROOT_DIR/.venv/bin/dbt"
  else
    die "dbt was not found in .venv. Dependency installation may have failed."
  fi
}

cd "$ROOT_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  die "Created .env from .env.example. Fill in Snowflake values, then rerun: bash scripts/setup_fresh_machine.sh"
fi

SYSTEM_PYTHON="$(find_system_python)"

if [[ ! -d "$ROOT_DIR/.venv" ]]; then
  log "Creating Python virtual environment"
  "$SYSTEM_PYTHON" -m venv "$ROOT_DIR/.venv"
fi

VENV_PYTHON="$(venv_python_path)"

if [[ "$INSTALL_REQUIREMENTS" == "1" ]]; then
  log "Installing Python, Snowflake, and dbt dependencies"
  "$VENV_PYTHON" -m pip install --upgrade pip
  "$VENV_PYTHON" -m pip install -r "$ROOT_DIR/requirements-pipeline.txt"
else
  log "Skipping dependency install because INSTALL_REQUIREMENTS=0"
fi

VENV_DBT="$(venv_dbt_path)"

if [[ "$START_AIRFLOW" == "1" ]]; then
  log "Starting Airflow with Docker"
  UNPAUSE_DAG=0 TRIGGER_DAG=0 bash "$ROOT_DIR/scripts/start_airflow_docker.sh"
else
  log "Skipping Airflow startup because START_AIRFLOW=0"
  export SKIP_AIRFLOW=1
fi

if [[ "$RUN_BOOTSTRAP" == "1" ]]; then
  log "Running Snowflake, 7-day backfill, dbt, and hourly DAG bootstrap"
  BOOTSTRAP_PYTHON_BIN="$VENV_PYTHON" \
    BOOTSTRAP_DBT_BIN="$VENV_DBT" \
    bash "$ROOT_DIR/scripts/bootstrap_new_snowflake_account.sh"
else
  log "Skipping project bootstrap because RUN_BOOTSTRAP=0"
fi

log "Fresh machine setup complete"
