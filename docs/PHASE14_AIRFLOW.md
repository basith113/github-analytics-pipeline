# Phase 14: Apache Airflow Orchestration

## Goal

Orchestrate the GitHub Analytics Pipeline with Apache Airflow so the hourly workflow runs in a repeatable production-style DAG.

Phase 13, the Power BI dashboard phase, is intentionally skipped for now. The project moves directly from Phase 12 documentation to Phase 14 orchestration.

## DAG Summary

Airflow DAG:

```text
scheduler/airflow/dags/github_pipeline_dag.py
```

Schedule:

```text
5 * * * *
```

The DAG runs every hour at minute 5. GH Archive usually publishes hourly files shortly after the hour, so this gives the source a small buffer.

## Workflow

```text
start
  -> validate_environment
  -> dbt_deps
  -> load_latest_hour
  -> dbt_run_incremental_models
  -> dbt_test_models
  -> dbt_source_freshness
  -> complete
```

## Task Responsibilities

| Task | Purpose |
|------|---------|
| `validate_environment` | Fails fast when required Snowflake variables or repo paths are missing. |
| `dbt_deps` | Installs dbt packages, including `dbt_utils`. |
| `load_latest_hour` | Runs `ingestion/incremental/load_latest_hour.py`. |
| `dbt_run_incremental_models` | Runs staging and mart dbt models by tag. |
| `dbt_test_models` | Runs dbt tests for staging, marts, and source-dependent tests. |
| `dbt_source_freshness` | Runs dbt source freshness checks for `github_archive`. |

## Required Environment Variables

Airflow workers must have:

```text
SNOWFLAKE_ACCOUNT
SNOWFLAKE_USER
SNOWFLAKE_PASSWORD
SNOWFLAKE_WAREHOUSE
SNOWFLAKE_DATABASE
SNOWFLAKE_SCHEMA
SNOWFLAKE_ROLE
```

Optional path overrides:

```text
PIPELINE_REPO_ROOT
PIPELINE_PYTHON_BIN
DBT_BIN
DBT_PROJECT_DIR
DBT_PROFILES_DIR
```

Defaults assume the DAG lives inside this repository:

| Variable | Default |
|----------|---------|
| `PIPELINE_REPO_ROOT` | Repository root inferred from the DAG file path |
| `PIPELINE_PYTHON_BIN` | Airflow worker Python executable |
| `DBT_BIN` | `dbt` from `PATH` |
| `DBT_PROJECT_DIR` | `dbt/github_dbt` |
| `DBT_PROFILES_DIR` | `dbt` |

## Local Airflow Setup Notes

Apache Airflow is best run on Linux, WSL, or Docker. On Windows, prefer WSL or Docker rather than native Windows execution.

Example WSL/Docker-style setup:

```bash
export AIRFLOW_HOME="$PWD/.airflow"
export AIRFLOW__CORE__DAGS_FOLDER="$PWD/scheduler/airflow/dags"
export PIPELINE_REPO_ROOT="$PWD"
export DBT_PROJECT_DIR="$PWD/dbt/github_dbt"
export DBT_PROFILES_DIR="$PWD/dbt"

airflow db migrate
airflow users create \
  --username admin \
  --password admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com

airflow scheduler
airflow webserver --port 8080
```

## Test the DAG

Validate that Airflow can import the DAG:

```bash
airflow dags list | grep github_analytics_pipeline
```

Run one task locally:

```bash
airflow tasks test github_analytics_pipeline validate_environment 2026-06-18
```

Run the pipeline manually from the UI or CLI:

```bash
airflow dags trigger github_analytics_pipeline
```

## Snowflake Account Caveat

Phase 12 found that the current `SNOWFLAKE_ACCOUNT` value returns:

```text
404 Not Found: post IE05791.snowflakecomputing.com:443/session/v1/login-request
```

Before running the full DAG, update `SNOWFLAKE_ACCOUNT` to the full account identifier from the Snowflake account URL. Depending on the Snowflake account, this is usually either:

- an org-account name, or
- an account locator with region/cloud suffix.

The DAG can be imported without a live Snowflake connection, but `load_latest_hour`, `dbt_run_incremental_models`, `dbt_test_models`, and `dbt_source_freshness` will fail until Snowflake connectivity is fixed.

## Monitoring and Failure Handling

Current Phase 14 monitoring:

- Airflow retries each task twice with a 5-minute delay.
- `max_active_runs=1` prevents overlapping hourly runs.
- `validate_environment` fails early for missing configuration.
- `notify_failure` logs the failed task, DAG run, and exception.

Future enhancements:

- Send Slack or email alerts from `notify_failure`.
- Store row-count metrics in an audit table.
- Add branch logic for skipped loads versus newly loaded files.
- Add a weekly full-refresh DAG.
- Add an Airflow dataset or sensor when upstream availability becomes predictable.

## Phase 14 Checklist

- [x] Airflow folder structure created
- [x] DAG file added
- [x] Hourly schedule configured
- [x] Ingestion task wired
- [x] dbt dependency, run, test, and freshness tasks wired
- [x] Failure callback added
- [x] Phase 14 documentation added
- [ ] DAG imported in Airflow
- [ ] `validate_environment` passes in Airflow
- [ ] Full DAG run succeeds after Snowflake account identifier is corrected

---

**Status**: DAG scaffold complete; moved to Phase 15 with runtime validation caveats documented  
**Phase**: 14 of 15  
**Next Phase**: Phase 15 - Portfolio Readiness
