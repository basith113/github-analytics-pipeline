# GitHub Analytics Pipeline - End-to-End Project Overview

## Executive Summary

This project is an end-to-end data engineering pipeline for GitHub public event analytics. It ingests hourly GH Archive event files, loads raw semi-structured JSON into Snowflake, transforms the data with dbt into analytics-ready staging and mart tables, validates quality with automated tests, and orchestrates the full workflow with Apache Airflow.

The result is a production-style analytics foundation that turns raw GitHub activity into trusted tables for reporting, exploration, and dashboarding.

## What This Project Does

The pipeline answers a practical question:

> How can raw GitHub event data be collected every hour, stored reliably, transformed into clean analytical models, and monitored for quality?

It does this by:

- Downloading hourly GitHub public event files from GH Archive.
- Loading raw JSON events into Snowflake `RAW` tables.
- Tracking each loaded file in a load audit table to prevent duplicate loads.
- Parsing nested JSON into clean dbt staging models.
- Building dimensional mart tables for actors, repositories, event types, and events.
- Running dbt tests and source freshness checks after each load.
- Scheduling the workflow with Airflow on an hourly cadence.

## Why This Project Exists

Raw event streams are useful but hard to analyze directly. GH Archive provides rich GitHub activity data, but each hourly file is compressed JSON with nested fields, inconsistent payload shapes, and high row volume.

This project solves that by building a repeatable data platform pattern:

- Land raw data without losing detail.
- Preserve load metadata for auditability.
- Transform only after raw data is safely stored.
- Model the data into clean tables with clear grain.
- Test the data before it is trusted for analysis.
- Schedule the process so new data arrives automatically.

The same pattern applies to many real business pipelines: product events, clickstream data, payment events, support tickets, application logs, and operational telemetry.

## Business Problem Solved

Without this pipeline, analysts would need to manually download JSON files, parse nested data, deduplicate records, and rebuild reports every time new GitHub activity arrives.

This project solves the problem by creating an automated, warehouse-backed data product:

- Analysts get query-ready tables instead of raw JSON files.
- Engineers get a reliable load history and repeatable transformations.
- Stakeholders can track repository, developer, and event activity over time.
- Data quality issues are surfaced through dbt tests and freshness checks.
- Hourly orchestration reduces manual work and makes the pipeline observable.

## End-to-End Architecture

```text
GH Archive hourly files
        |
        v
Python ingestion layer
        |
        v
Snowflake RAW schema
        |
        v
dbt staging models
        |
        v
dbt mart models
        |
        v
dbt tests and freshness checks
        |
        v
Airflow hourly orchestration
        |
        v
Analytics-ready Snowflake tables
```

## Data Flow

| Step | Layer | What Happens | Main Files or Objects |
|------|-------|--------------|-----------------------|
| 1 | Source | GH Archive publishes compressed hourly GitHub event files. | `https://data.gharchive.org/{YYYY-MM-DD-H}.json.gz` |
| 2 | Ingestion | Python finds the latest available file, skips it if already loaded, downloads events, and loads them to Snowflake. | `ingestion/incremental/load_latest_hour.py` |
| 3 | Raw storage | Snowflake stores each event as JSON in `VARIANT` plus source file and load metadata. | `GITHUB_DBT.RAW.GITHUB_EVENTS` |
| 4 | Audit tracking | Each hourly file load is recorded with row count and status. | `GITHUB_DBT.RAW.LOAD_HISTORY` |
| 5 | Staging | dbt parses JSON into typed event, actor, repo, timestamp, and payload columns. | `stg_github_events`, `stg_actors`, `stg_repositories`, `stg_event_types` |
| 6 | Marts | dbt builds dimensional tables and an incremental fact table. | `fact_events`, `dim_actor`, `dim_repository`, `dim_event_type` |
| 7 | Quality | dbt checks uniqueness, not-null constraints, accepted values, relationships, and source freshness. | dbt YAML tests and `stg_events_freshness.sql` |
| 8 | Orchestration | Airflow runs the workflow hourly with retries and task-level visibility. | `scheduler/airflow/dags/github_pipeline_dag.py` |

## Component Design

### GH Archive

GH Archive is the source system. It publishes public GitHub events as hourly compressed JSON files. This makes it a good source for practicing real data engineering because the data is public, high-volume, nested, and time-based.

### Python Ingestion

Python is used for extraction and loading because it is flexible for HTTP downloads, JSON handling, environment configuration, logging, and Snowflake connectivity.

The incremental loader:

- Determines the latest available GH Archive file.
- Checks `RAW.LOAD_HISTORY` before loading to avoid duplicates.
- Downloads and validates the hourly file.
- Loads the events into Snowflake.
- Records success or failure metadata.

### Snowflake Raw Layer

Snowflake is used as the analytical warehouse. The raw layer keeps the original event JSON in `VARIANT` format so downstream models can evolve without losing source detail.

Raw objects:

| Object | Grain | Purpose |
|--------|-------|---------|
| `GITHUB_DBT.RAW.GITHUB_EVENTS` | One row per GitHub event | Stores raw event JSON and source file metadata. |
| `GITHUB_DBT.RAW.LOAD_HISTORY` | One row per source file load | Tracks file name, file hour, row count, status, and load metadata. |

### dbt Transformation Layer

dbt owns the transformation logic, documentation, and tests.

The dbt project converts raw JSON into two clean layers:

- Staging models: clean, typed, reusable views/tables close to the source grain.
- Mart models: dimensional tables designed for analytics and BI.

The main fact model, `fact_events`, is incremental and uses `event_id` as the unique key so hourly runs can merge new events without rebuilding all historical data.

### Airflow Orchestration

Airflow schedules and monitors the pipeline. The DAG runs hourly at minute 5 and has retries configured for operational resilience.

DAG name:

```text
github_analytics_pipeline
```

Airflow UI:

```text
http://localhost:8080
```

Local login used during validation:

```text
admin / admin
```

## Data Model

### Raw Layer

| Table | Grain | Description |
|-------|-------|-------------|
| `RAW.GITHUB_EVENTS` | One row per event | Raw GitHub event JSON stored as Snowflake `VARIANT`. |
| `RAW.LOAD_HISTORY` | One row per GH Archive file load | Load audit table used for idempotency, monitoring, and debugging. |

### Staging Layer

In the validated dbt dev target, these models are written under `GITHUB_DBT.STAGING_STAGING`.

| Model | Grain | Description |
|-------|-------|-------------|
| `STG_GITHUB_EVENTS` | One row per event | Parses raw JSON into event, actor, repository, timestamp, payload, source file, and load columns. |
| `STG_ACTORS` | One row per actor | Deduplicates actors and derives first/last seen timestamps and bot/user classification. |
| `STG_REPOSITORIES` | One row per repository | Deduplicates repositories and extracts owner and repository short name. |
| `STG_EVENT_TYPES` | One row per event type | Summarizes event type counts, categories, first occurrence, and last occurrence. |

### Mart Layer

In the validated dbt dev target, these models are written under `GITHUB_DBT.STAGING_MARTS`.

| Model | Grain | Description |
|-------|-------|-------------|
| `FACT_EVENTS` | One row per GitHub event | Main incremental fact table for activity analysis. |
| `DIM_ACTOR` | One row per actor | Actor dimension with user/bot classification and activity dates. |
| `DIM_REPOSITORY` | One row per repository | Repository dimension with owner/name parsing and activity dates. |
| `DIM_EVENT_TYPE` | One row per event type | Event type dimension with categories and distribution metrics. |

Note: The schema names `STAGING_STAGING` and `STAGING_MARTS` come from dbt's target schema behavior. The profile target schema is `STAGING`, and dbt appends the custom model schemas `STAGING` and `MARTS`.

## Airflow Workflow

The Airflow DAG runs tasks in this order:

```text
start
  -> validate_environment
  -> dbt_deps
  -> load_latest_hour
  -> dbt_run_incremental_models
  -> dbt_test_models
  -> complete

dbt_run_incremental_models
  -> dbt_source_freshness
  -> complete
```

| Task | Purpose |
|------|---------|
| `start` | Marks the beginning of the DAG run. |
| `validate_environment` | Verifies Snowflake and dbt environment variables and paths. |
| `dbt_deps` | Installs dbt dependencies, or skips if `dbt_utils` is already installed. |
| `load_latest_hour` | Runs the Python incremental loader for the latest GH Archive file. |
| `dbt_run_incremental_models` | Runs staging and mart models. |
| `dbt_test_models` | Runs dbt quality tests for staging, marts, and sources. |
| `dbt_source_freshness` | Checks that raw source data is fresh. |
| `complete` | Marks the workflow as complete. |

Schedule:

```text
5 * * * *
```

That means the DAG runs every hour at minute 5.

## Reliability and Data Quality

This project includes several reliability patterns that are expected in production-style pipelines.

| Pattern | Why It Matters |
|---------|----------------|
| Load history table | Prevents reloading the same hourly file multiple times. |
| Raw JSON retention | Preserves complete source data for replay and future model changes. |
| Snowflake staged `COPY INTO` load | Loads large hourly files faster and more reliably than row-by-row inserts. |
| dbt incremental fact model | Processes new data efficiently during hourly runs. |
| dbt uniqueness tests | Protects event and dimension grains. |
| dbt not-null tests | Ensures required keys and timestamps are present. |
| dbt accepted-values tests | Confirms event and actor categories stay inside expected values. |
| dbt relationship tests | Validates fact-to-dimension joins. |
| Source freshness check | Detects late or missing raw loads. |
| Airflow retries | Gives transient failures another chance before the run is marked failed. |

## Latest Validated Runtime Snapshot

The following state was validated on 2026-06-18 after a successful Airflow run.

Latest successful DAG run:

```text
scheduled__2026-06-18T13:05:00+00:00
```

Successful tasks:

```text
start
validate_environment
dbt_deps
load_latest_hour
dbt_run_incremental_models
dbt_test_models
dbt_source_freshness
complete
```

Verified Snowflake row counts:

| Snowflake Object | Row Count |
|------------------|----------:|
| `GITHUB_DBT.RAW.GITHUB_EVENTS` | 480,902 |
| `GITHUB_DBT.RAW.LOAD_HISTORY` | 4 |
| `GITHUB_DBT.STAGING_STAGING.STG_GITHUB_EVENTS` | 480,902 |
| `GITHUB_DBT.STAGING_MARTS.FACT_EVENTS` | 480,902 |
| `GITHUB_DBT.STAGING_MARTS.DIM_ACTOR` | 144,084 |
| `GITHUB_DBT.STAGING_MARTS.DIM_REPOSITORY` | 191,634 |
| `GITHUB_DBT.STAGING_MARTS.DIM_EVENT_TYPE` | 10 |

This confirms that the raw load, dbt transformations, mart tables, tests, and Airflow orchestration are all working together.

## Key Engineering Improvements Made

During the final validation work, several issues were fixed to make the pipeline actually run end to end.

| Improvement | Impact |
|-------------|--------|
| Replaced row-by-row Snowflake inserts with staged `COPY INTO` loading. | Made raw event ingestion faster and more reliable for hourly files. |
| Added a Snowflake bootstrap script. | Creates the database, schemas, and raw tables consistently. |
| Made Airflow `dbt_deps` offline-friendly. | Skips dependency installation if `dbt_utils` is already available. |
| Adjusted dbt test syntax for dbt 1.10 compatibility. | Prevented Airflow's dbt runtime from failing on newer YAML syntax. |
| Fixed the custom freshness test aggregate logic. | Avoided invalid aggregate usage in a `WHERE` clause. |
| Corrected actor and repository staging grain. | Ensured one row per actor and one row per repository. |
| Validated the DAG in a running Airflow container. | Confirmed the orchestration is operational, not only scaffolded. |

## How to Run and Inspect

### Fresh Machine Setup After GitHub Clone

On a different machine, the project can be started from a clean clone with one setup script after the Snowflake details are filled in.

Minimum software needed on the machine:

- Git
- Python 3.11 or newer
- Git Bash, WSL, or another Bash shell
- Docker Desktop, if you want Airflow to run hourly
- A Snowflake account/user/role/warehouse with permission to create the project database and schemas

Fresh setup flow:

```bash
git clone <your-repo-url>
cd github-analytics-pipeline
cp .env.example .env
```

Fill `.env` with the Snowflake values, then run:

```bash
bash scripts/setup_fresh_machine.sh
```

That script:

- Creates a local `.venv`.
- Installs local ingestion, Snowflake, and dbt dependencies from `requirements-pipeline.txt`.
- Starts Airflow with Docker using `docker-compose.airflow.yml`.
- Creates Snowflake foundation objects.
- Loads rolling last 7 days of GH Archive history.
- Runs dbt models, tests, and freshness checks.
- Enables and triggers the hourly Airflow DAG.

If the machine does not have Docker yet, run the setup without Airflow:

```bash
START_AIRFLOW=0 bash scripts/setup_fresh_machine.sh
```

Then install Docker Desktop later and run:

```bash
bash scripts/start_airflow_docker.sh
SKIP_BACKFILL=1 SKIP_DBT=1 bash scripts/bootstrap_new_snowflake_account.sh
```

### Move to a New Snowflake Account

When you want to point the project at a different Snowflake account, update only the Snowflake values in `.env`, then run:

```bash
bash scripts/bootstrap_new_snowflake_account.sh
```

The script does the full new-account setup:

- Loads the updated `.env` values.
- Creates the Snowflake database, schemas, and raw tables.
- Loads a rolling 7 days of GH Archive history.
- Runs dbt staging and mart models.
- Runs dbt tests and source freshness checks.
- Restarts the local `github-airflow` container if it exists.
- Unpauses `github_analytics_pipeline`.
- Triggers one immediate DAG run.

After that, the Airflow DAG continues on its normal hourly schedule:

```text
5 * * * *
```

Optional controls:

```bash
SKIP_BACKFILL=1 bash scripts/bootstrap_new_snowflake_account.sh
SKIP_DBT=1 bash scripts/bootstrap_new_snowflake_account.sh
SKIP_AIRFLOW=1 bash scripts/bootstrap_new_snowflake_account.sh
RESTART_AIRFLOW_CONTAINER=0 bash scripts/bootstrap_new_snowflake_account.sh
```

Required `.env` values:

```text
SNOWFLAKE_ACCOUNT
SNOWFLAKE_USER
SNOWFLAKE_PASSWORD
SNOWFLAKE_WAREHOUSE
SNOWFLAKE_DATABASE
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE
```

### Access Airflow

Open:

```text
http://localhost:8080
```

Use the `github_analytics_pipeline` DAG.

Common Airflow commands:

```powershell
docker exec github-airflow airflow dags list
docker exec github-airflow airflow dags unpause github_analytics_pipeline
docker exec github-airflow airflow dags trigger github_analytics_pipeline
docker exec github-airflow airflow tasks states-for-dag-run github_analytics_pipeline <dag_run_id>
```

### Bootstrap Snowflake Foundation Objects

Run from the repository root:

```powershell
python scripts/bootstrap_snowflake_foundation.py
```

This creates the expected Snowflake database, raw schema, staging schema, marts schema, and raw audit tables.

### Run One Incremental Load Without Airflow

Run from the repository root:

```powershell
python ingestion/incremental/load_latest_hour.py
```

### Run dbt Manually

Run from `dbt/github_dbt`:

```powershell
dbt deps --profiles-dir ..
dbt run --profiles-dir .. --select tag:staging tag:marts
dbt test --profiles-dir .. --select tag:staging tag:marts source:github_archive+
dbt source freshness --profiles-dir .. --select github_archive
```

### Verify Data in Snowflake

Use these queries:

```sql
SELECT COUNT(*) AS raw_events
FROM GITHUB_DBT.RAW.GITHUB_EVENTS;

SELECT file_name, file_hour, row_count, status, load_ts
FROM GITHUB_DBT.RAW.LOAD_HISTORY
ORDER BY file_hour DESC;

SELECT COUNT(*) AS staged_events
FROM GITHUB_DBT.STAGING_STAGING.STG_GITHUB_EVENTS;

SELECT COUNT(*) AS fact_events
FROM GITHUB_DBT.STAGING_MARTS.FACT_EVENTS;

SELECT COUNT(*) AS actors
FROM GITHUB_DBT.STAGING_MARTS.DIM_ACTOR;

SELECT COUNT(*) AS repositories
FROM GITHUB_DBT.STAGING_MARTS.DIM_REPOSITORY;
```

## Analytical Use Cases Enabled

The mart layer supports questions such as:

- Which GitHub event types are most common?
- Which repositories are receiving the most activity?
- Which actors are most active?
- How much activity is human-generated versus bot-generated?
- How does GitHub activity trend by hour, day, week, or month?
- Which repositories or actors recently became active?
- Is the raw source data fresh enough for reporting?

## Portfolio and Interview Talking Points

Strong ways to explain this project:

- "I built an hourly GitHub event analytics pipeline using Python, Snowflake, dbt, and Airflow."
- "The ingestion layer is idempotent because each GH Archive file is tracked in a load history table."
- "Raw events are stored in Snowflake as `VARIANT` so the original JSON remains available for future transformations."
- "dbt parses the raw data into staging models and builds dimensional marts for analytics."
- "The fact table is incremental, which keeps hourly dbt runs efficient."
- "Airflow orchestrates ingestion, transformation, testing, and freshness checks in one monitored DAG."
- "I validated the end-to-end run in Airflow and confirmed the final Snowflake row counts."

Resume-ready version:

```text
Built an end-to-end GitHub analytics data pipeline using Python, Snowflake, dbt, and Airflow to ingest hourly GH Archive JSON files, load raw events with idempotent audit tracking, transform data into dimensional marts, run automated quality checks, and orchestrate the workflow on an hourly schedule.
```

## Current Limitations and Future Enhancements

| Area | Current State | Future Enhancement |
|------|---------------|-------------------|
| BI dashboard | Phase 13 Power BI work was skipped for now. | Build Power BI or Streamlit dashboard on top of the mart tables. |
| Secrets | Local `.env` variables are used for development. | Move credentials to Airflow connections, a secrets backend, or a cloud secret manager. |
| Deployment | Validated locally with an Airflow container. | Package with Docker Compose or deploy Airflow to a managed environment. |
| Monitoring | Airflow task status and dbt tests are available. | Add alerting through email, Slack, or PagerDuty. |
| CI/CD | Manual validation is currently used. | Add GitHub Actions for linting, dbt compile, and dbt test in CI. |
| Schema naming | dbt dev target writes to `STAGING_STAGING` and `STAGING_MARTS`. | Customize `generate_schema_name` if cleaner schema names are preferred. |
| Historical backfill | Project includes backfill capability and hourly incremental load. | Add parameterized Airflow backfill runs for selected date ranges. |

## Final Project Summary

This project demonstrates a complete data engineering workflow:

```text
Ingest -> Store Raw -> Transform -> Test -> Orchestrate -> Analyze
```

It solves the problem of turning raw, nested, hourly GitHub event files into clean, trusted, analytics-ready Snowflake tables. The final validated pipeline loads raw data, tracks load history, builds dbt staging and mart models, runs quality checks, and completes successfully through Airflow.
