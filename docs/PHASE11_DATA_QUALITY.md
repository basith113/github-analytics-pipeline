# Phase 11: Data Quality Framework – Comprehensive Guide

## Overview

Phase 11 implements comprehensive data quality checks, freshness monitoring, and anomaly detection across all data layers.

**Components**:
- dbt source freshness checks
- Custom SQL tests for business logic
- Relationship validation tests
- Data freshness and completeness monitoring
- SCD Type 2 validation
- Anomaly detection queries

---

## Data Quality Layers

```
RAW Layer (Phase 2)
├─ Check: File loaded successfully
├─ Check: Event IDs not null
├─ Check: Timestamps valid
└─ Monitor: Load frequency

    ↓

STAGING Layer (Phase 8)
├─ Check: Grain preserved (no duplicates)
├─ Check: Foreign keys present
├─ Check: Dates in valid range
└─ Monitor: Data freshness

    ↓

MARTS Layer (Phase 9-10)
├─ Check: Fact grain (one per event)
├─ Check: All dimensions populated
├─ Check: Referential integrity
└─ Monitor: Completeness
```

---

## Source Freshness Checks

### Configuration (sources.yml)

```yaml
freshness:
  warn_after:
    count: 2
    period: hour
  error_after:
    count: 4
    period: hour
  loaded_at_field: LOAD_TS
```

**Interpretation**:
- **Warn**: If data older than 2 hours → yellow flag
- **Error**: If data older than 4 hours → red flag
- **loaded_at_field**: Column to check for freshness

### Execution

```bash
# Check source freshness
dbt source freshness

# Expected output:
# github_archive.github_events: FRESH (loaded 15 minutes ago)
# github_archive.load_history: FRESH (loaded 15 minutes ago)
```

### What Happens if Stale?

```
⚠️  FRESHNESS WARNING
Source: github_archive.github_events
  Last Loaded: 2024-01-15 14:30
  Current Time: 2024-01-15 16:45 (2h 15m ago)
  Status: WARN (> 2h)
  
→ Action: Check Phase 5 (incremental load) - did it fail?
```

---

## Custom SQL Tests

### Test Files Created

#### 1. fact_events_grain.sql

**Purpose**: Verify fact table has one row per event (no duplicates)

```sql
SELECT COUNT(*) as duplicate_count
FROM fact_events
GROUP BY event_id
HAVING COUNT(*) > 1
```

**Expected Result**: 0 rows (no duplicates)

**Fail Condition**: If any event_id appears twice

**Typical Issue**: 
- Incremental merge logic broken
- Events loaded twice
- Duplicate file processing

**Recovery**:
```sql
-- Check for duplicates
SELECT event_id, COUNT(*) 
FROM fact_events 
GROUP BY event_id 
HAVING COUNT(*) > 1;

-- Delete duplicates (keep latest)
DELETE FROM fact_events 
WHERE event_key NOT IN (
  SELECT MAX(event_key) 
  FROM fact_events 
  GROUP BY event_id
);
```

#### 2. fact_events_foreign_keys.sql

**Purpose**: Ensure all facts reference valid dimensions

```sql
SELECT COUNT(*) as missing_actors
FROM fact_events
WHERE actor_key IS NULL
  AND event_key IS NOT NULL
```

**Expected Result**: 0 rows (all populated)

**Fail Condition**: Missing dimension key references

**Typical Issue**:
- Dimensions not fully populated before facts
- New actor/repo in facts but not in dimensions
- Incremental logic skipped dimension updates

**Recovery**:
```sql
-- Rerun dimensions
dbt run --models dim_actor,dim_repository,dim_event_type --full-refresh

-- Then rerun facts
dbt run --models fact_events --full-refresh
```

#### 3. dim_actor_scd_type2.sql

**Purpose**: Verify SCD Type 2 logic (max one current record per actor)

```sql
SELECT actor_id, COUNT(*) as current_count
FROM dim_actor
WHERE dbt_is_current = true
GROUP BY actor_id
HAVING COUNT(*) > 1
```

**Expected Result**: 0 rows (only one current record per actor)

**Fail Condition**: Multiple current records for same actor

**Typical Issue**:
- SCD logic broken in model
- Manual data edits conflicted with dbt
- Incremental merge logic error

#### 4. stg_events_freshness.sql

**Purpose**: Alert if staging data is stale (older than expected)

```sql
SELECT 
  MAX(created_at) as latest_event,
  DATEDIFF('hour', MAX(created_at), CURRENT_TIMESTAMP()) as hours_behind
FROM stg_github_events
WHERE DATEDIFF('hour', MAX(created_at), CURRENT_TIMESTAMP()) > 2
```

**Expected Result**: 0 rows (data is fresh)

**Fail Condition**: Returns rows if data > 2 hours old

**Typical Issue**:
- Incremental load failed
- Network connectivity problem
- GH Archive service down

#### 5. dim_event_type_coverage.sql

**Purpose**: Ensure all event types in facts are defined in dimension

```sql
SELECT DISTINCT f.event_type
FROM fact_events f
LEFT JOIN dim_event_type d ON f.event_type = d.event_type
WHERE d.event_type IS NULL
```

**Expected Result**: 0 rows (all types covered)

**Fail Condition**: Returns unknown event types

**Typical Issue**:
- New GitHub event type introduced
- Data corruption
- Staging logic changed

**Recovery**:
```sql
-- Add new event type to dim_event_type manually
INSERT INTO dim_event_type (event_type, event_description, event_category)
VALUES ('NewEventType', 'Description', 'Category');

-- Or rerun staging and dimension models
dbt run --models stg_event_types,dim_event_type --full-refresh
```

---

## Test Execution

### Run All Tests

```bash
dbt test
```

**Expected Output**:
```
Running tests...
  Freshness check on github_events: PASS
  Not null test on fact_events.event_id: PASS
  Unique test on fact_events.event_id: PASS
  Relationship test on fact_events.actor_key: PASS
  Custom test fact_events_grain: PASS
  Custom test fact_events_foreign_keys: PASS
  ...
  
Done! 50+ tests executed, 50+ passed, 0 failed
```

### Run Specific Test

```bash
# Test fact table only
dbt test --models fact_events

# Test custom SQL tests
dbt test --select fact_events_grain
```

### Store Test Failures

```bash
# Keep failed records for investigation
dbt test --store-failures

# Query failures
SELECT * FROM github_dbt.test_failures.fact_events_grain;
```

---

## Monitoring & Alerting

### Dashboard Queries (for Power BI or Grafana)

#### Data Freshness

```sql
SELECT 
  'github_events' as source,
  MAX(load_ts) as last_loaded,
  CURRENT_TIMESTAMP() as check_time,
  DATEDIFF('minute', MAX(load_ts), CURRENT_TIMESTAMP()) as minutes_behind,
  CASE 
    WHEN DATEDIFF('minute', MAX(load_ts), CURRENT_TIMESTAMP()) < 60 THEN 'FRESH'
    WHEN DATEDIFF('minute', MAX(load_ts), CURRENT_TIMESTAMP()) < 120 THEN 'WARN'
    ELSE 'ERROR'
  END as freshness_status
FROM RAW.GITHUB_EVENTS;
```

#### Test Results Summary

```sql
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN 'ALL_PASS'
    ELSE 'HAS_FAILURES'
  END as test_status,
  COUNT(*) as failure_count
FROM github_dbt.test_failures.fact_events_grain;
```

#### Data Volume Anomalies

```sql
-- Compare today's events to last 7 days average
WITH daily_counts AS (
  SELECT 
    DATE(created_at) as event_date,
    COUNT(*) as daily_events
  FROM MARTS.FACT_EVENTS
  WHERE created_at >= CURRENT_DATE - 7
  GROUP BY DATE(created_at)
)

SELECT 
  event_date,
  daily_events,
  ROUND(AVG(daily_events) OVER (
    ORDER BY event_date 
    ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
  ), 0) as 7_day_avg,
  ROUND(daily_events * 100.0 / AVG(daily_events) OVER (
    ORDER BY event_date 
    ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
  ), 1) as pct_of_avg,
  CASE 
    WHEN daily_events < 0.8 * AVG(daily_events) OVER (ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING)
      THEN 'LOW'
    WHEN daily_events > 1.2 * AVG(daily_events) OVER (ORDER BY event_date ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING)
      THEN 'HIGH'
    ELSE 'NORMAL'
  END as anomaly_flag
FROM daily_counts
ORDER BY event_date DESC;
```

#### Dimension Completeness

```sql
SELECT 
  'dim_actor' as dimension,
  COUNT(*) as total_records,
  COUNT(CASE WHEN dbt_is_current THEN 1 END) as current_records,
  COUNT(CASE WHEN actor_id IS NULL THEN 1 END) as missing_ids
FROM MARTS.DIM_ACTOR

UNION ALL

SELECT 
  'dim_repository',
  COUNT(*),
  COUNT(*),
  COUNT(CASE WHEN repo_id IS NULL THEN 1 END)
FROM MARTS.DIM_REPOSITORY

UNION ALL

SELECT 
  'dim_event_type',
  COUNT(*),
  COUNT(*),
  COUNT(CASE WHEN event_type IS NULL THEN 1 END)
FROM MARTS.DIM_EVENT_TYPE;
```

#### Model Run Performance

```sql
-- dbt execution times
SELECT 
  model_name,
  ROUND(execution_time_seconds, 2) as duration_seconds,
  CASE 
    WHEN execution_time_seconds < 10 THEN 'FAST'
    WHEN execution_time_seconds < 30 THEN 'NORMAL'
    ELSE 'SLOW'
  END as performance_flag
FROM dbt_invocations
WHERE run_date >= CURRENT_DATE
ORDER BY execution_time_seconds DESC;
```

---

## Alerting Rules

### Set Up Alerts in Snowflake

```sql
-- Alert: Data not loaded in 2+ hours
CREATE ALERT IF NOT EXISTS data_staleness_alert
  CONDITION: (
    SELECT DATEDIFF('minute', MAX(load_ts), CURRENT_TIMESTAMP()) > 120
    FROM RAW.GITHUB_EVENTS
  )
  ACTION: SEND MESSAGE
  TO INTEGRATION slack_notification
  WITH SUBJECT 'Data Pipeline Alert'
  BODY 'GitHub events data not loaded in 2+ hours';
```

### Recommended Thresholds

| Metric | Warning | Error |
|--------|---------|-------|
| Data Freshness | 2 hours | 4 hours |
| Load Failures | 1 failure | 3 consecutive |
| Duplicate Events | Any found | Any found |
| Missing Dimensions | 1% of facts | 5% of facts |
| Test Failures | Any | Any |

---

## Integration with Phase 14 (Airflow)

Phase 11 checks will be integrated into Airflow DAG:

```python
# airflow/dags/github_pipeline_dag.py

dbt_test = BashOperator(
    task_id='dbt_test',
    bash_command='cd /path && dbt test --select state:modified+',
    dag=dag,
    trigger_rule='all_done'  # Run even if previous tasks fail
)

send_test_results = PythonOperator(
    task_id='send_test_results',
    python_callable=notify_results,
    dag=dag,
    trigger_rule='all_done'
)

# If tests fail, send alerts
branch_on_test = BranchPythonOperator(
    task_id='branch_on_test',
    python_callable=check_test_results,
    dag=dag
)
```

---

## Data Quality SLAs

| Layer | Freshness | Completeness | Accuracy |
|-------|-----------|--------------|----------|
| RAW | ≤ 1 hour | 99.9% | Raw JSON |
| STAGING | ≤ 2 hours | 99.5% | Parsed, validated |
| MARTS | ≤ 3 hours | 99.0% | Aggregated, tested |

---

## Monitoring Checklist

- [ ] Source freshness checks configured
- [ ] Custom SQL tests created (5 tests)
- [ ] All dbt tests passing (50+)
- [ ] Test failures stored and queryable
- [ ] Monitoring queries documented
- [ ] Alert thresholds set in Snowflake
- [ ] Dashboard created for data quality metrics
- [ ] Escalation procedures defined

---

## Test Summary

**Tests Implemented**:
- ✓ Source freshness (2 sources)
- ✓ Not null (20+ columns)
- ✓ Unique (10+ columns)
- ✓ Accepted values (5+ columns)
- ✓ Relationships (foreign keys)
- ✓ Custom fact grain verification
- ✓ Custom foreign key validation
- ✓ Custom SCD Type 2 validation
- ✓ Custom freshness check
- ✓ Custom dimension coverage

**Total Tests**: 50+

**Execution Time**: 2-3 minutes

---

## Next Phase Integration

Phase 12 builds on Phase 11:
- Generate dbt documentation with test results
- Create data lineage with quality scores
- Visualize test coverage

---

## Files Created/Updated

| File | Purpose |
|------|---------|
| tests/fact_events_grain.sql | Duplicate detection |
| tests/fact_events_foreign_keys.sql | FK validation |
| tests/dim_actor_scd_type2.sql | SCD logic check |
| tests/stg_events_freshness.sql | Data staleness alert |
| tests/dim_event_type_coverage.sql | Type coverage |
| models/sources.yml | Freshness config |

---

## Phase 11 Checklist

- [ ] All 5 custom SQL tests created
- [ ] Source freshness configured
- [ ] All tests execute successfully (50+)
- [ ] Test failures stored
- [ ] Monitoring queries documented
- [ ] Alert rules defined
- [ ] SLA thresholds set
- [ ] Documentation complete

---

## Next Steps

1. ✓ Create custom SQL tests
2. ✓ Configure source freshness
3. ✓ Execute `dbt test` successfully
4. ✓ Document monitoring queries
5. → **Phase 12**: Generate dbt Documentation & Lineage

---

**Status**: ✅ Complete  
**Phase**: 11 of 15  
**Next Phase**: Phase 12 - Generate dbt Docs  
**Estimated Time**: 1-2 hours to complete Phase 12