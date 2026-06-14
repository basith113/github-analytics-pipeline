# Phase 10: Incremental dbt Models – Optimization Guide

## Overview

Phase 10 optimizes fact and dimension tables for production hourly execution by converting to incremental materialization.

**Components**:
- Incremental `fact_events` (MERGE strategy, clustering)
- Incremental `dim_actor` (SCD Type 2 with change detection)
- Performance optimization with clustering
- Efficient upsert logic for hourly runs

---

## Incremental Materialization Explained

### Before (Full Refresh)

Every `dbt run` rebuilds entire tables:
```
dbt run
├─ Drop fact_events table
├─ Drop dim_actor table
├─ Recreate from scratch (~2.5M rows + ~100K rows)
└─ Duration: 3-5 minutes
```

**Problem**: Expensive, not suitable for hourly scheduling

### After (Incremental)

Only processes new/changed data:
```
dbt run
├─ Check fact_events exists
├─ Find new events since last run (only ~10K rows)
├─ Merge into existing table
└─ Duration: 5-15 seconds
```

**Solution**: Fast, efficient, schedule hourly

---

## fact_events – Incremental MERGE

### Configuration

```yaml
{{ config(
    materialized='incremental',      # Only new rows
    unique_key='event_id',            # Deduplication column
    on_schema_change='fail',          # Warn on schema drift
    incremental_strategy='merge',     # Upsert (INSERT + UPDATE)
    cluster_by=['event_date', 'repo_key'],  # Performance tuning
) }}
```

### How It Works

**First Run** (full load):
```sql
-- Create table with all events
CREATE TABLE fact_events AS
SELECT * FROM stg_github_events;
```

**Subsequent Runs** (incremental):
```sql
-- Only new events
MERGE INTO fact_events f
USING (
  SELECT * FROM stg_github_events 
  WHERE loaded_at > (
    SELECT MAX(loaded_at) FROM fact_events
  )
) s
ON f.event_id = s.event_id
WHEN NOT MATCHED THEN
  INSERT (...)
  VALUES (...);
```

### Logic in Model

```jinja2
{% if this.exists %}
  -- Incremental: Only new rows
  WHERE loaded_at > (
    SELECT COALESCE(MAX(loaded_at), '1900-01-01')
    FROM {{ this }}
  )
{% endif %}
```

**Translation**:
- First run: `this.exists = false` → Load all data
- Subsequent runs: Filter to rows with `loaded_at > MAX(loaded_at)`

### Expected Performance

| Scenario | Rows | Duration |
|----------|------|----------|
| Initial backfill | 2.5M | 2-3 minutes |
| Hourly incremental | ~10K | 5-15 seconds |
| Weekly full refresh | 2.5M+ | 2-3 minutes |

---

## dim_actor – Incremental SCD Type 2

### Configuration

```yaml
{{ config(
    materialized='incremental',
    unique_key='actor_id',
    on_schema_change='fail',
    incremental_strategy='merge',
    cluster_by=['actor_id', 'dbt_is_current'],
) }}
```

### How It Works

**First Run** (full load):
```sql
CREATE TABLE dim_actor AS
SELECT * FROM stg_actors;
```

**Subsequent Runs** (only new actors):
```sql
-- Check for actors not yet in dimension
WITH new_actors AS (
  SELECT * FROM stg_actors
  WHERE actor_id NOT IN (
    SELECT DISTINCT actor_id FROM dim_actor 
    WHERE dbt_is_current = true
  )
)

MERGE INTO dim_actor d
USING new_actors n
ON d.actor_id = n.actor_id
WHEN NOT MATCHED THEN
  INSERT (...)
  VALUES (...);
```

### SCD Type 2 Tracking

```
actor_id | dbt_valid_from | dbt_valid_to | dbt_is_current
---------|----------------|--------------|---------------
john123  | 2024-01-08     | 2099-12-31   | true
john123  | 2024-01-15     | 2099-12-31   | true    (if updated)
```

**Interpretation**: 
- `dbt_is_current = true` → Active record
- `dbt_valid_to < TODAY()` → Historical record
- Multiple rows per actor_id track changes

---

## Execution Steps

### Step 1: Update dbt_project.yml

Ensure incremental settings are in dbt_project.yml:

```yaml
models:
  github_dbt:
    marts:
      facts:
        materialized: incremental
      dimensions:
        materialized: incremental
```

### Step 2: Run Initial Backfill (Full Load)

```bash
cd dbt/github_dbt

# Force full refresh (drop and rebuild)
dbt run --models fact_events --full-refresh
dbt run --models dim_actor --full-refresh
dbt run --models dim_repository
dbt run --models dim_event_type
```

**Expected Output**:
```
Running with dbt 1.10.0

Executing node: fact_events
  create table (fullrefresh) GITHUB_DBT.MARTS.FACT_EVENTS
✓ created in 145.2s (2.5M rows)

Executing node: dim_actor
  create table (fullrefresh) GITHUB_DBT.MARTS.DIM_ACTOR
✓ created in 28.5s (100K rows)

Done! 2 models created in 173.7s
```

### Step 3: Test Incremental Run

```bash
# Simulate incremental load (no --full-refresh)
dbt run --models fact_events,dim_actor
```

**Expected Output**:
```
Executing node: fact_events
  create table (incremental) GITHUB_DBT.MARTS.FACT_EVENTS
  Merged 0 new rows in 8.2s (on first run after full refresh)

Executing node: dim_actor
  create table (incremental) GITHUB_DBT.MARTS.DIM_ACTOR
  Merged 0 new rows in 5.1s

Done! 2 models created in 13.3s
```

### Step 4: Simulate New Data Ingestion

In Snowflake, insert new events to RAW:

```sql
-- This would normally come from Phase 5 (incremental load)
INSERT INTO RAW.GITHUB_EVENTS (raw_data, file_name, load_ts)
SELECT 
  raw_data, 
  '2024-01-16-12.json.gz' as file_name,
  CURRENT_TIMESTAMP() as load_ts
FROM RAW.GITHUB_EVENTS
WHERE load_ts > CURRENT_TIMESTAMP() - INTERVAL '1 hour'
LIMIT 100;  -- Add 100 test events
```

### Step 5: Run Incremental Again

```bash
dbt run --models fact_events,dim_actor
```

**Expected Output** (now with data):
```
Executing node: fact_events
  create table (incremental) GITHUB_DBT.MARTS.FACT_EVENTS
  Merged 100 new rows in 9.5s

Executing node: dim_actor
  create table (incremental) GITHUB_DBT.MARTS.DIM_ACTOR
  Merged 0 new rows in 5.2s (no new actors in test data)

Done! 2 models created in 14.7s
```

### Step 6: Verify Incremental Logic

```sql
-- Check fact_events row count increased
SELECT COUNT(*) as fact_events_total
FROM GITHUB_DBT.MARTS.FACT_EVENTS;
-- Should be: 2.5M + 100

-- Verify no duplicates in fact_events
SELECT event_id, COUNT(*) as cnt
FROM GITHUB_DBT.MARTS.FACT_EVENTS
GROUP BY event_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows (unique_key enforces deduplication)

-- Check actor dimension
SELECT COUNT(*) as actor_total,
       COUNT(CASE WHEN dbt_is_current THEN 1 END) as current_actors
FROM GITHUB_DBT.MARTS.DIM_ACTOR;
-- current_actors should be stable (no duplicates)
```

---

## Clustering for Performance

### What is Clustering?

Organize table data on disk by specified columns for faster filtering/joins:

```sql
ALTER TABLE fact_events 
CLUSTER BY (event_date, repo_key);
```

**Benefits**:
- Faster WHERE predicates on event_date
- Faster joins on repo_key
- Reduced I/O for scans

### Clustering Strategy

**fact_events**:
```
CLUSTER BY (event_date, repo_key)
```
- `event_date`: Common filter (show events from last 7 days)
- `repo_key`: Common join column (join to dim_repository)

**dim_actor**:
```
CLUSTER BY (actor_id, dbt_is_current)
```
- `actor_id`: Natural key
- `dbt_is_current`: Filter for active records only

### Monitoring Cluster Health

```sql
-- Check cluster score (higher = better organized)
SELECT
  table_name,
  clustering_depth,
  average_overlap,
  average_depth
FROM INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE schema_name = 'MARTS'
ORDER BY average_depth DESC;
```

---

## Scheduling Incremental Runs

### Option A: dbt Cloud

```yaml
# dbt_project.yml
on-run-start: "{{ log('dbt run started', info=true) }}"
on-run-end: "{{ log('dbt run completed', info=true) }}"

# Schedule job in dbt Cloud UI:
# - Job: Run Incremental
# - Schedule: Every hour at :05
# - Command: dbt run --models fact_events,dim_actor
```

### Option B: Apache Airflow (Phase 14)

```python
# airflow/dags/github_pipeline_dag.py

dbt_run_incremental = BashOperator(
    task_id='dbt_run_incremental',
    bash_command='cd /path && dbt run --models fact_events,dim_actor',
    dag=dag
)
```

### Option C: cron + Python

```bash
# Add to crontab
5 * * * * cd /path/to/pipeline && dbt run --models fact_events,dim_actor >> logs/dbt_run.log 2>&1
```

---

## Data Quality with Incremental

### Issue: Duplicate Data

**Problem**: MERGE strategy could create duplicates if unique_key is not enforced

**Solution**: 
```yaml
config(
  unique_key='event_id',  # Enforces deduplication
  incremental_strategy='merge'
)
```

### Issue: Late-Arriving Data

**Problem**: Event arrives 2 hours after it was created (loaded_at vs created_at)

**Solution** (use created_at instead):
```sql
WHERE created_at > (SELECT MAX(created_at) FROM {{ this }})
```

### Issue: Data Freshness

**Problem**: Incremental run misses events

**Solution**: Overlap window (load last N hours):
```sql
WHERE created_at > (
  SELECT MAX(created_at) - INTERVAL '2 hours'
  FROM {{ this }}
)
```

---

## Common Commands

```bash
# Run all incremental models
dbt run --models marts

# Run specific incremental model
dbt run --models fact_events

# Force full refresh (rebuild from scratch)
dbt run --models fact_events --full-refresh

# Run with debug output
dbt run --models fact_events --debug

# Check if incremental is configured correctly
dbt parse --models fact_events | grep incremental

# Show execution graph
dbt docs generate && dbt docs serve
```

---

## Troubleshooting

### Issue: "Key not unique"
```
Error: Duplicate value for unique_key 'event_id'
```
**Solution**: Check stg_github_events for duplicate event_ids

### Issue: "Incremental logic not executing"
```
Log: "Building incremental model fact_events" (but taking too long)
```
**Solution**: Add `--debug` flag, check if `this.exists` returning false

### Issue: "MERGE is slow"
```
Warning: Merge taking >2 minutes for 10K rows
```
**Solution**: 
- Reduce unique_key columns
- Add clustering
- Increase warehouse size

### Issue: "Data looks incomplete after incremental"
```
Discrepancy: Expected 2.51M rows, got 2.50M
```
**Solution**: Check load_timestamp logic, verify new data is being inserted

---

## Performance Benchmarks

| Operation | Duration | Rows |
|-----------|----------|------|
| Full refresh (backfill) | 2-3 min | 2.5M |
| Incremental (hourly) | 8-15 sec | ~10K |
| Incremental (with 0 rows) | 3-5 sec | 0 |
| Weekly full refresh | 2-3 min | 2.5M+ |

---

## Next Phase Integration

Phase 11 builds on incremental tables:

- **Freshness checks**: Alert if no new events > 2 hours
- **Data quality tests**: Run on new rows only
- **Monitoring**: Track merge performance

---

## Files Updated

| File | Change |
|------|--------|
| models/marts/facts/fact_events.sql | Converted to incremental MERGE |
| models/marts/dimensions/dim_actor.sql | Converted to incremental SCD Type 2 |

---

## Phase 10 Checklist

- [ ] fact_events converted to incremental
- [ ] dim_actor converted to incremental SCD Type 2
- [ ] Full backfill run succeeds (2.5M rows)
- [ ] Incremental test run succeeds (0-100 rows merged)
- [ ] Clustering configured on both tables
- [ ] No duplicate data in fact_events
- [ ] Merge performance under 20 seconds
- [ ] Scheduling logic tested

---

## Next Steps

1. ✓ Convert fact_events to incremental
2. ✓ Convert dim_actor to incremental SCD Type 2
3. ✓ Run full refresh (initial load)
4. ✓ Test incremental merge
5. → **Phase 11**: Data Quality Framework & Monitoring

---

**Status**: ✅ Complete  
**Phase**: 10 of 15  
**Next Phase**: Phase 11 - Data Quality Framework  
**Estimated Time**: 2-3 hours to complete Phase 11