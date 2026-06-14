# Data Dictionary

## Overview

This dictionary describes the analytics-ready GitHub event dataset built by the pipeline. The authoritative technical metadata lives in the dbt project under `dbt/github_dbt/models`; this page is the portfolio-friendly companion for reviewers and dashboard users.

## Lineage

```
GH Archive JSON files
  -> RAW.GITHUB_EVENTS
  -> STAGING.STG_GITHUB_EVENTS
  -> STAGING.STG_ACTORS
  -> STAGING.STG_REPOSITORIES
  -> STAGING.STG_EVENT_TYPES
  -> MARTS.DIM_ACTOR
  -> MARTS.DIM_REPOSITORY
  -> MARTS.DIM_EVENT_TYPE
  -> MARTS.FACT_EVENTS
```

## Source Tables

### RAW.GITHUB_EVENTS

Raw GitHub event records loaded from GH Archive hourly files.

| Column | Description | Quality Rule |
|--------|-------------|--------------|
| `raw_data` | Complete GitHub event JSON stored as a variant payload. | Not null |
| `file_name` | Source file name in `YYYY-MM-DD-H.json.gz` format. | Not null, unique |
| `load_ts` | Timestamp when the event was loaded into Snowflake. | Not null |
| `_inserted_at` | Legacy/system insert timestamp. | Informational |
| `_file_row_number` | Row number inside the compressed GH Archive file. | Informational |

### RAW.LOAD_HISTORY

Audit table that prevents duplicate loads and records file-level load outcomes.

| Column | Description | Quality Rule |
|--------|-------------|--------------|
| `file_name` | Source file name and natural load key. | Not null, unique |
| `load_ts` | Timestamp when the file load finished. | Not null |
| `file_hour` | Hour represented by the GH Archive file. | Informational |
| `row_count` | Number of records loaded from the file. | Monitored |
| `file_size_bytes` | Compressed file size. | Informational |
| `status` | Load outcome: `SUCCESS`, `FAILED`, `SKIPPED`, or `RETRY`. | Accepted values |
| `error_message` | Failure detail when status is `FAILED`. | Nullable |
| `retry_count` | Number of retry attempts. | Monitored |
| `load_duration_seconds` | File load duration. | Monitored |
| `loaded_by` | Script or user that loaded the file. | Informational |

## Staging Models

### STAGING.STG_GITHUB_EVENTS

Clean event-level staging table parsed from raw JSON.

| Column | Description |
|--------|-------------|
| `event_id` | Unique GitHub event ID. |
| `event_type` | GitHub event type such as `PushEvent`, `PullRequestEvent`, or `IssuesEvent`. |
| `actor_id` | GitHub user or bot ID that triggered the event. |
| `actor_login` | GitHub username or bot name. |
| `actor_type` | Actor category: `User` or `Bot`. |
| `repo_id` | GitHub repository ID. |
| `repo_name` | Repository full name in `owner/name` format. |
| `created_at` | Event timestamp in UTC. |
| `payload` | Event-specific JSON payload. |
| `source_file` | GH Archive file that supplied the event. |
| `loaded_at` | Raw-layer load timestamp. |
| `dbt_loaded_at` | Timestamp when dbt created the staging row. |
| `dbt_run_id` | dbt run identifier for lineage tracking. |

### STAGING.STG_ACTORS

One row per actor, derived from `stg_github_events`.

| Column | Description |
|--------|-------------|
| `actor_id` | Unique GitHub actor ID. |
| `actor_login` | GitHub username or bot name. |
| `actor_type` | Actor category: `User` or `Bot`. |
| `first_seen_at` | Earliest event timestamp for the actor. |
| `last_seen_at` | Latest event timestamp for the actor. |
| `days_active` | Number of days between first and last observed activity. |
| `dbt_loaded_at` | Timestamp when dbt created the staging row. |

### STAGING.STG_REPOSITORIES

One row per repository, derived from `stg_github_events`.

| Column | Description |
|--------|-------------|
| `repo_id` | Unique GitHub repository ID. |
| `repo_name` | Repository full name in `owner/name` format. |
| `repo_owner` | Owner parsed from `repo_name`. |
| `repo_short_name` | Repository name parsed from `repo_name`. |
| `first_event_at` | Earliest observed event for the repository. |
| `last_event_at` | Latest observed event for the repository. |
| `days_active` | Number of observed active days. |
| `dbt_loaded_at` | Timestamp when dbt created the staging row. |

### STAGING.STG_EVENT_TYPES

One row per GitHub event type with distribution metrics.

| Column | Description |
|--------|-------------|
| `event_type` | GitHub event type name. |
| `event_count` | Number of events of this type. |
| `unique_actors` | Distinct actors who triggered the event type. |
| `unique_repos` | Distinct repositories that received the event type. |
| `first_occurrence` | Earliest timestamp for this event type. |
| `last_occurrence` | Latest timestamp for this event type. |
| `percent_of_total_events` | Share of all events represented by this type. |
| `event_description` | Business-readable event description. |
| `dbt_loaded_at` | Timestamp when dbt created the staging row. |

## Mart Models

### MARTS.DIM_ACTOR

Actor dimension with Type 2 SCD-style validity fields.

| Column | Description |
|--------|-------------|
| `actor_key` | Surrogate key generated from `actor_id`. |
| `actor_id` | GitHub actor natural key. |
| `actor_login` | GitHub username or bot name. |
| `actor_type` | Actor category: `User` or `Bot`. |
| `is_bot` | Boolean bot indicator. |
| `first_seen_at` | Earliest event timestamp for the actor. |
| `last_seen_at` | Latest event timestamp for the actor. |
| `days_active` | Number of observed active days. |
| `dbt_valid_from` | Start timestamp for the current dimension version. |
| `dbt_valid_to` | End timestamp for the current dimension version. |
| `dbt_is_current` | Current-row flag. |
| `dbt_created_at` | Row creation timestamp. |
| `dbt_updated_at` | Row update timestamp. |

### MARTS.DIM_REPOSITORY

Repository dimension for owner/name analysis and repository filtering.

| Column | Description |
|--------|-------------|
| `repo_key` | Surrogate key generated from `repo_id`. |
| `repo_id` | GitHub repository natural key. |
| `repo_name` | Repository full name in `owner/name` format. |
| `repo_owner` | Owner parsed from `repo_name`. |
| `repo_short_name` | Repository short name parsed from `repo_name`. |
| `first_event_at` | Earliest observed repository event. |
| `last_event_at` | Latest observed repository event. |
| `days_active` | Number of observed active days. |
| `is_test_repo` | Flag for repositories whose names look like tests or examples. |
| `dbt_created_at` | Row creation timestamp. |
| `dbt_updated_at` | Row update timestamp. |

### MARTS.DIM_EVENT_TYPE

Event type dimension with business categories and distribution metrics.

| Column | Description |
|--------|-------------|
| `event_type_key` | Surrogate key generated from `event_type`. |
| `event_type` | GitHub event type name. |
| `event_description` | Business-readable event description. |
| `event_count` | Number of events of this type. |
| `unique_actors` | Distinct actors who triggered this type. |
| `unique_repos` | Distinct repositories involved in this type. |
| `percent_of_total_events` | Share of total activity represented by this type. |
| `first_occurrence` | Earliest observed timestamp for this type. |
| `last_occurrence` | Latest observed timestamp for this type. |
| `event_category` | Business category such as `Activity`, `Engagement`, or `Collaboration`. |
| `dbt_created_at` | Row creation timestamp. |
| `dbt_updated_at` | Row update timestamp. |

### MARTS.FACT_EVENTS

Transaction fact table with one row per GitHub event.

| Column | Description |
|--------|-------------|
| `event_key` | Surrogate key generated from `event_id`. |
| `event_id` | GitHub event natural key. |
| `actor_key` | Foreign key to `dim_actor`. |
| `repo_key` | Foreign key to `dim_repository`. |
| `event_type_key` | Foreign key to `dim_event_type`. |
| `event_type` | Denormalized event type for query performance. |
| `actor_id` | Denormalized actor ID. |
| `actor_login` | Denormalized actor login. |
| `repo_id` | Denormalized repository ID. |
| `repo_name` | Denormalized repository name. |
| `created_at` | Event timestamp in UTC. |
| `event_date` | Date extracted from `created_at`. |
| `event_hour` | Hour extracted from `created_at`. |
| `event_day_of_week` | Day name extracted from `created_at`. |
| `event_week` | Week number extracted from `created_at`. |
| `event_month` | Month number extracted from `created_at`. |
| `event_year` | Year extracted from `created_at`. |
| `source_file` | GH Archive source file. |
| `loaded_at` | Raw-layer load timestamp. |
| `dbt_created_at` | Fact row creation timestamp. |

## Business Glossary

| Term | Meaning |
|------|---------|
| Actor | GitHub user or bot that triggered an event. |
| Repository | GitHub project receiving the event. |
| Event | Single GitHub activity record from GH Archive. |
| Fact | Transactional model used for metrics and time-series analysis. |
| Dimension | Descriptive model used to slice, filter, and group facts. |
| SCD | Slowly changing dimension pattern for tracking historical attribute changes. |
| Freshness | Measure of how recently source data was loaded. |
| Lineage | Dependency path from source data through staging and mart models. |

## Core Analytics Questions

- Which repositories receive the most GitHub activity?
- Which actors are most active over the selected time window?
- How does activity vary by hour, day, and event type?
- What share of activity is automated bot behavior?
- Are raw loads and mart models fresh enough for dashboard use?

## Documentation Artifacts

The dbt-generated site adds searchable model pages, column-level documentation, test metadata, and an interactive lineage graph. Generate it with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1
```
