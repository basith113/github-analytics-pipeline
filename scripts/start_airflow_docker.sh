#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAG_ID="${DAG_ID:-github_analytics_pipeline}"
AIRFLOW_CONTAINER="${AIRFLOW_CONTAINER:-github-airflow}"
UNPAUSE_DAG="${UNPAUSE_DAG:-0}"
TRIGGER_DAG="${TRIGGER_DAG:-0}"

log() {
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    die "Docker Compose was not found. Install Docker Desktop with Compose."
  fi
}

wait_for_airflow() {
  local attempt

  for attempt in {1..90}; do
    if docker exec "$AIRFLOW_CONTAINER" airflow dags list >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

command -v docker >/dev/null 2>&1 || die "Docker was not found. Install Docker Desktop first."
[[ -f "$ROOT_DIR/.env" ]] || die "Missing .env. Copy .env.example to .env and fill Snowflake values."

cd "$ROOT_DIR"

log "Starting Airflow Docker container"
docker_compose -f docker-compose.airflow.yml up -d --build

log "Waiting for Airflow to become ready"
wait_for_airflow || die "Airflow container started, but the Airflow CLI did not become ready."

if [[ "$UNPAUSE_DAG" == "1" ]]; then
  log "Unpausing DAG: $DAG_ID"
  docker exec "$AIRFLOW_CONTAINER" airflow dags unpause "$DAG_ID"
fi

if [[ "$TRIGGER_DAG" == "1" ]]; then
  log "Triggering DAG: $DAG_ID"
  docker exec "$AIRFLOW_CONTAINER" airflow dags trigger "$DAG_ID"
fi

log "Airflow is available at http://localhost:8080"
log "Login: admin / admin"

