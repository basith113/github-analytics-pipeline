# Phase 7: dbt Foundation Setup

## Overview

Phase 7 establishes the dbt project structure, configuration, and initial models that form the foundation for data transformation.

**Components**:
- dbt project initialization and configuration
- Snowflake profile setup (dev/prod schemas)
- Source documentation (RAW tables)
- Initial macros for JSON parsing
- First staging model (stg_github_events)

---

## What's Included

### 1. dbt Project Structure

```
dbt/
├── github_dbt/                          ← dbt project root
│   ├── dbt_project.yml                  ← Project configuration
│   ├── models/
│   │   ├── staging/
│   │   │   ├── stg_github_events.sql    ← Parse raw JSON
│   │   │   └── stg_github_events.yml    ← Tests & documentation
│   │   ├── marts/
│   │   │   ├── dimensions/              ← To be created Phase 9
│   │   │   └── facts/                   ← To be created Phase 9
│   │   └── sources.yml                  ← RAW table documentation
│   ├── macros/
│   │   ├── get_latest_events.sql        ← Helper for time-based filtering
│   │   └── parse_github_event.sql       ← Extract JSON fields
│   ├── tests/                           ← Phase 11
│   ├── snapshots/                       ← Phase 10
│   └── analysis/                        ← Phase 6 queries
├── profiles.yml                         ← Snowflake connection
```

### 2. Profiles.yml – Snowflake Connection

**Location**: `dbt/profiles.yml`

**Configuration**:
```yaml
github_dbt:
  outputs:
    dev:
      schema: STAGING      # Development environment
    prod:
      schema: MARTS        # Production environment
  target: dev              # Default target
```

**Credentials** (from .env):
- `SNOWFLAKE_ACCOUNT` – Snowflake account identifier
- `SNOWFLAKE_USER` – dbt user
- `SNOWFLAKE_PASSWORD` – User password
- `SNOWFLAKE_WAREHOUSE` – Compute warehouse
- `SNOWFLAKE_ROLE` – Transformer role

**Usage**:
```bash
# Run in dev (STAGING schema)
dbt run

# Run in prod (MARTS schema)
dbt run --target prod
```

### 3. dbt_project.yml – Project Configuration

**Key Settings**:
- **Project name**: github_dbt
- **Version**: 1.0.0
- **dbt version**: >=1.10.0, <2.0.0
- **Model paths**: models/ folder
- **Test paths**: tests/ folder
- **Staging schema**: STAGING (dev) / MARTS (prod)

**Model Configuration**:
```yaml
models:
  github_dbt:
    staging:
      materialized: view          # Lightweight transforms
    marts:
      dimensions:
        materialized: table       # Slowly changing dimensions
      facts:
        materialized: incremental # Only new data each run
```

### 4. Sources.yml – RAW Table Documentation

**Purpose**: Document raw tables so dbt knows where data comes from

**Tables Documented**:

#### GITHUB_EVENTS
- **Grain**: One row per GitHub event
- **Volume**: ~2.5M from 7-day backfill, ~10K/hour incremental
- **Columns**:
  - `raw_data` (VARIANT) – Complete event JSON
  - `file_name` – Source file identifier
  - `load_ts` – Load timestamp

#### LOAD_HISTORY
- **Grain**: One row per file load
- **Volume**: 168 rows from backfill, 1 row/hour incremental
- **Purpose**: Audit trail and deduplication

**Freshness Checks**:
```yaml
warn_after: 2 hours
error_after: 4 hours
```

**Tests Applied**:
- `not_null` – All critical columns
- `unique` – Event IDs and file names
- `accepted_values` – Status field

### 5. Macros – Reusable SQL Components

#### get_latest_events.sql
```sql
{% macro get_latest_events(days=7, event_type=none, limit=100000) %}
  -- Returns events from past N days with optional type filter
{% endmacro %}

-- Usage:
SELECT * FROM {{ get_latest_events(days=7, event_type='PushEvent') }}
```

#### parse_github_event.sql
```sql
{% macro parse_github_event() %}
  -- Extracts: event_id, event_type, actor_id, actor_login, 
  --           repo_id, repo_name, created_at, payload, etc.
{% endmacro %}

-- Usage:
SELECT 
  {{ parse_github_event() }}
FROM raw.github_events
```

### 6. Staging Model – stg_github_events

**Purpose**: Parse raw JSON into clean columns

**Input**: `RAW.GITHUB_EVENTS` (~2.5M records)

**Output**: `STAGING.STG_GITHUB_EVENTS`

**Columns Created**:
```
event_id          INTEGER     (unique, not null)
event_type        VARCHAR     (PushEvent, etc.)
actor_id          INTEGER     (developer/bot ID)
actor_login       VARCHAR     (username)
actor_type        VARCHAR     (User or Bot)
repo_id           INTEGER     (repository ID)
repo_name         VARCHAR     (owner/repo)
created_at        TIMESTAMP   (when event occurred)
payload           VARIANT     (raw event details)
source_file       VARCHAR     (GH Archive file)
loaded_at         TIMESTAMP   (load timestamp)
dbt_loaded_at     TIMESTAMP   (transformation timestamp)
dbt_run_id        VARCHAR     (lineage)
```

**Tests** (stg_github_events.yml):
- `event_id`: not_null, unique
- `event_type`: not_null, accepted_values (valid types only)
- `actor_id`: not_null
- `repo_id`: not_null
- `created_at`: not_null

---

## Setup Instructions

### Step 1: Verify Installation

```bash
cd dbt/github_dbt
dbt --version
# Expected: dbt 1.10.0 or higher
```

### Step 2: Configure Environment

Ensure `.env` has Snowflake credentials:
```env
SNOWFLAKE_ACCOUNT=xy12345
SNOWFLAKE_USER=dbt_user
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_ROLE=TRANSFORMER
```

### Step 3: Test dbt Connection

```bash
dbt debug
```

**Expected Output**:
```
Connection test: [OK]
All checks passed!
```

**If fails**:
- Check .env variables
- Verify Snowflake account/user/password
- Ensure COMPUTE_WH exists and is running
- Run `snowflake_setup_validation.sql` in Snowflake

### Step 4: Seed Configuration

```bash
dbt seed
```

(No seeds yet – added in later phases)

### Step 5: Test Source Freshness

```bash
dbt source freshness
```

**Expected Output**:
```
github_archive.github_events: FRESH
github_archive.load_history: FRESH
```

### Step 6: Run Staging Model

```bash
dbt run --models stg_github_events
```

**Expected Output**:
```
Running with dbt 1.10.0
Found 1 model, 0 tests, 0 snapshots

Executing node:
  create view GITHUB_DBT.STAGING.STG_GITHUB_EVENTS
✓ 1 created in 45.32s
```

### Step 7: Test Staging Model

```bash
dbt test --models stg_github_events
```

**Expected Output**:
```
Running tests...
  Freshness check on stg_github_events.event_id: PASS
  Unique test on stg_github_events.event_id: PASS
  Not null test on stg_github_events.event_type: PASS
  ... (all tests pass)

3 passed in 30.2s
```

### Step 8: Generate Documentation

```bash
dbt docs generate
dbt docs serve
```

Opens http://localhost:8000 with:
- Project DAG (sources → stg_github_events)
- Model documentation
- Column descriptions
- Test coverage

---

## Verification Checklist

After Phase 7 completes:

- [ ] dbt project initialized in `dbt/github_dbt/`
- [ ] `profiles.yml` configured with Snowflake credentials
- [ ] `dbt_project.yml` created with proper structure
- [ ] `sources.yml` documents RAW tables
- [ ] 2 macros created (get_latest_events, parse_github_event)
- [ ] `stg_github_events` model runs successfully
- [ ] All 8 tests on stg_github_events pass
- [ ] `dbt debug` succeeds (connection validated)
- [ ] `dbt source freshness` shows FRESH status
- [ ] Documentation generated and viewable

---

## Integration with Later Phases

### Phase 8: Staging Models & Tests
- Create additional staging models if needed
- Add comprehensive dbt tests
- Document data lineage

### Phase 9: Dimensional Modeling
- Create dimensions (dim_actor, dim_repository, dim_event_type)
- Create facts (fact_events, fact_push_events)
- Build star schema

### Phase 10: Incremental Models
- Convert fact tables to incremental (only process new data)
- Optimize performance for hourly loads

### Phase 11: Data Quality Framework
- Add freshness checks
- Implement relationship tests
- Alert on anomalies

### Phase 14: Airflow Orchestration
- Schedule dbt runs hourly with dbt Cloud or Airflow
- Coordinate with ingestion pipeline

---

## Common Commands

```bash
# Enter dbt project
cd dbt/github_dbt

# Run all models
dbt run

# Run specific model
dbt run --models stg_github_events

# Run and test
dbt test

# Dry run (parse only)
dbt parse

# View compiled SQL
dbt parse --write-manifest

# Generate docs
dbt docs generate
dbt docs serve

# Full clean and rebuild
dbt clean
dbt run
dbt test

# Switch to prod target
dbt run --target prod --models stg_github_events
```

---

## Troubleshooting

### Issue: "Source file not found"
```
Error: Unable to find source 'github_archive.github_events'
```
**Solution**: Ensure RAW.GITHUB_EVENTS table exists and is populated (Phase 4)

### Issue: "Connection failed"
```
Error: Failed to connect to Snowflake
```
**Solution**: Run `dbt debug`, check .env variables, verify credentials

### Issue: "Tests failing on event_type"
```
Error: Unaccepted value: UnknownEventType
```
**Solution**: Add new event type to accepted_values in stg_github_events.yml

### Issue: "dbt slow/timing out"
```
Error: Query timed out
```
**Solution**: Increase warehouse size, add clustering to GITHUB_EVENTS, reduce batch size

---

## Files Created

| File | Purpose |
|------|---------|
| dbt/profiles.yml | Snowflake connection config |
| dbt/github_dbt/dbt_project.yml | Project settings |
| dbt/github_dbt/models/sources.yml | RAW table documentation |
| dbt/github_dbt/models/staging/stg_github_events.sql | Parse JSON model |
| dbt/github_dbt/models/staging/stg_github_events.yml | Tests & docs |
| dbt/github_dbt/macros/get_latest_events.sql | Time-based filter macro |
| dbt/github_dbt/macros/parse_github_event.sql | JSON parser macro |

---

## Next Steps

1. ✓ Run `dbt debug` to verify connection
2. ✓ Execute `dbt run` to create stg_github_events
3. ✓ Run `dbt test` to validate data quality
4. ✓ Run `dbt docs generate` for documentation
5. → **Phase 8**: Create additional staging models and tests

---

**Status**: ✅ Complete  
**Phase**: 7 of 15  
**Next Phase**: Phase 8 - Staging Models & Tests  
**Estimated Time**: 2-3 hours to complete Phase 8