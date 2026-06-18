# Phase 15: Portfolio Readiness

## Goal

Package the GitHub Analytics Pipeline as a portfolio-ready data engineering project with a clear story, visible artifacts, resume-ready impact statements, and honest remaining caveats.

Phase 13 Power BI work is skipped for now. Phase 15 focuses on presenting the implemented pipeline layers: ingestion, Snowflake storage, dbt transformations, data quality, dbt documentation, and Airflow orchestration.

## Portfolio Story

This project demonstrates an end-to-end analytics engineering pipeline for GitHub event data:

1. Ingest hourly GH Archive files with Python.
2. Load raw JSON events into Snowflake.
3. Track load history for idempotency and recovery.
4. Transform raw events into staging and mart models with dbt.
5. Model dimensions and facts for analytics workloads.
6. Add data quality checks, freshness checks, and custom dbt tests.
7. Generate dbt documentation and model screenshots.
8. Orchestrate hourly execution with an Airflow DAG scaffold.

## Implemented Capabilities

| Area | Status | Evidence |
|------|--------|----------|
| Project structure | Complete | `README.md`, `configs/`, `ingestion/`, `sql/`, `dbt/`, `docs/`, `scheduler/` |
| GH Archive ingestion | Implemented | `ingestion/backfill/load_last_7_days.py`, `ingestion/incremental/load_latest_hour.py` |
| Snowflake load tracking | Implemented | `RAW.GITHUB_EVENTS`, `RAW.LOAD_HISTORY`, loader utilities |
| dbt staging | Implemented | `stg_github_events`, `stg_actors`, `stg_repositories`, `stg_event_types` |
| dbt marts | Implemented | `dim_actor`, `dim_repository`, `dim_event_type`, `fact_events` |
| Incremental strategy | Implemented | Incremental `fact_events` and `dim_actor` configs |
| Data quality | Implemented | Generic tests, custom SQL tests, freshness checks |
| dbt docs | Implemented locally | `docs/screenshots/`, `dbt/github_dbt/target/static_index.html` |
| Airflow orchestration | Scaffold complete | `scheduler/airflow/dags/github_pipeline_dag.py` |
| Power BI dashboard | Skipped for now | Phase 13 intentionally deferred |

## Portfolio Artifacts

| Artifact | Path |
|----------|------|
| Architecture guide | `docs/ARCHITECTURE.md` |
| Setup guide | `docs/SETUP_GUIDE.md` |
| Data dictionary | `docs/DATA_DICTIONARY.md` |
| dbt docs phase guide | `docs/PHASE12_DBT_DOCS.md` |
| Airflow phase guide | `docs/PHASE14_AIRFLOW.md` |
| Portfolio one-pager | `docs/PORTFOLIO_ONE_PAGER.md` |
| dbt overview screenshot | `docs/screenshots/dbt-lineage.png` |
| Fact model screenshot | `docs/screenshots/dbt-fact_events.png` |
| Actor dimension screenshot | `docs/screenshots/dbt-dim_actor.png` |
| Airflow DAG | `scheduler/airflow/dags/github_pipeline_dag.py` |

## Resume Bullets

- Built an end-to-end GitHub events analytics pipeline using Python, Snowflake, dbt, and Airflow to ingest, transform, test, document, and orchestrate hourly GH Archive data.
- Designed an idempotent ingestion layer with load-history tracking to prevent duplicate file processing and support recovery from failed hourly loads.
- Modeled raw GitHub JSON into analytics-ready dbt staging, dimension, and fact models with incremental processing for cost-efficient warehouse execution.
- Implemented dbt data quality coverage with uniqueness, null, accepted-value, relationship, freshness, and custom SQL tests across staging and mart layers.
- Generated dbt documentation artifacts, model lineage screenshots, and a business-facing data dictionary to make the warehouse contract reviewable.
- Created an Airflow DAG scaffold for hourly ingestion, dbt transformation, dbt tests, and freshness checks with retries and failure logging.

## Interview Talking Points

### Architecture

The project separates ingestion, storage, transformation, quality, documentation, and orchestration into clear layers. That makes each part independently testable and easier to operate.

### Idempotency

The pipeline tracks loaded GH Archive files in `RAW.LOAD_HISTORY`, so scheduled runs can safely skip files already loaded successfully.

### Cost Control

dbt incremental models process only newly loaded events after the initial backfill. This reduces Snowflake compute compared with rebuilding mart tables every hour.

### Data Quality

The project combines generic dbt tests with custom tests for fact grain, foreign keys, event type coverage, freshness, and SCD current-record logic.

### Documentation

dbt docs, screenshots, and the manual data dictionary turn the pipeline into a readable contract for reviewers, analysts, and future maintainers.

### Orchestration

The Airflow DAG wires the production workflow: validate environment, install dbt dependencies, load latest data, run dbt models, run tests, and check freshness.

## Known Caveats

| Caveat | Current State | Next Action |
|--------|---------------|-------------|
| Snowflake account identifier | `SNOWFLAKE_ACCOUNT=IE05791` returns a Snowflake login 404 | Replace with the full account identifier from the Snowflake URL |
| Full dbt catalog | Metadata-only docs generated with `--empty-catalog` | Regenerate full dbt docs after Snowflake connectivity is fixed |
| Airflow runtime | DAG syntax is valid, but Airflow is not installed in local `.venv` | Validate DAG import in WSL, Docker, or a Linux Airflow environment |
| Power BI | Phase 13 skipped | Add dashboard screenshots later if needed |
| README encoding | Some existing symbols render as mojibake in the current README | Optional polish pass to normalize README encoding |

## Final Polish Checklist

- [x] README points to implemented docs and screenshots
- [x] Phase 13 marked as skipped for now
- [x] Phase 14 Airflow DAG scaffold added
- [x] Phase 15 portfolio-readiness document added
- [x] Portfolio one-pager added
- [x] Resume bullets drafted
- [x] Known caveats documented honestly
- [ ] Fix `SNOWFLAKE_ACCOUNT`
- [ ] Run full dbt docs generation with warehouse catalog
- [ ] Import DAG in a real Airflow runtime
- [ ] Add final screenshots for Airflow UI after import
- [ ] Optional: add Power BI dashboard later

## Suggested Repository Summary

```text
End-to-end data engineering project for GitHub event analytics. Ingests hourly GH Archive JSON data with Python, stores raw events in Snowflake, transforms them with dbt into dimensional marts, applies automated data quality checks, generates dbt documentation, and orchestrates the workflow with Apache Airflow.
```

---

**Status**: Portfolio package drafted; final runtime validation pending Snowflake/Airflow environment fixes  
**Phase**: 15 of 15  
**Next Step**: Final runtime validation and optional dashboard polish
