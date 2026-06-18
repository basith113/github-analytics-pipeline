# GitHub Analytics Pipeline: Portfolio One-Pager

## Project Summary

End-to-end data engineering project for GitHub event analytics. The pipeline ingests hourly GH Archive JSON files with Python, loads raw events into Snowflake, transforms them with dbt into analytics-ready staging and mart models, applies automated data quality checks, generates dbt documentation, and scaffolds hourly orchestration with Apache Airflow.

## Problem

GitHub event data is high-volume, semi-structured, and published hourly. A useful analytics pipeline needs to ingest new files reliably, avoid duplicate loads, preserve raw data, transform JSON into queryable models, validate data quality, and run on a schedule.

## Solution

The project implements a layered data platform:

```text
GH Archive
  -> Python ingestion
  -> Snowflake RAW tables
  -> dbt staging models
  -> dbt mart models
  -> dbt tests and docs
  -> Airflow orchestration
```

## Technical Highlights

| Capability | Implementation |
|------------|----------------|
| Source ingestion | Python GH Archive client and hourly incremental loader |
| Storage | Snowflake RAW schema with JSON event payloads |
| Idempotency | `RAW.LOAD_HISTORY` prevents duplicate file loads |
| Transformation | dbt staging, dimension, and fact models |
| Incremental processing | Incremental `fact_events` and `dim_actor` models |
| Data quality | dbt generic tests, custom SQL tests, and freshness checks |
| Documentation | dbt docs screenshots plus manual data dictionary |
| Orchestration | Airflow DAG scaffold for hourly pipeline runs |

## Core Models

| Layer | Models |
|-------|--------|
| Sources | `github_archive.github_events`, `github_archive.load_history` |
| Staging | `stg_github_events`, `stg_actors`, `stg_repositories`, `stg_event_types` |
| Dimensions | `dim_actor`, `dim_repository`, `dim_event_type` |
| Facts | `fact_events` |

## Evidence

| Artifact | Path |
|----------|------|
| Main README | `README.md` |
| Architecture guide | `docs/ARCHITECTURE.md` |
| Data dictionary | `docs/DATA_DICTIONARY.md` |
| dbt docs guide | `docs/PHASE12_DBT_DOCS.md` |
| Airflow guide | `docs/PHASE14_AIRFLOW.md` |
| Portfolio readiness guide | `docs/PHASE15_PORTFOLIO_READINESS.md` |
| dbt overview screenshot | `docs/screenshots/dbt-lineage.png` |
| fact_events screenshot | `docs/screenshots/dbt-fact_events.png` |
| dim_actor screenshot | `docs/screenshots/dbt-dim_actor.png` |
| Airflow DAG | `scheduler/airflow/dags/github_pipeline_dag.py` |

## Resume Version

Built an end-to-end GitHub events analytics pipeline using Python, Snowflake, dbt, and Airflow, including idempotent hourly ingestion, dimensional modeling, incremental transformations, automated dbt data quality checks, generated lineage documentation, and an Airflow orchestration DAG.

## Current Caveats

- `SNOWFLAKE_ACCOUNT` needs the full account identifier before live Snowflake/dbt runs will succeed.
- dbt docs were generated in metadata-only mode, so `catalog.json` is an empty catalog stub.
- Airflow DAG syntax is valid, but DAG import must be tested in a real Airflow runtime.
- Power BI dashboard work was intentionally skipped for now.

## Next Polish Options

- Fix Snowflake account identifier and rerun full dbt docs generation.
- Import the DAG in WSL or Docker Airflow and capture Airflow UI screenshots.
- Add a lightweight dashboard later if Phase 13 is resumed.
- Normalize README encoding for cleaner GitHub rendering.
