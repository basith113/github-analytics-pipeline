# Phase 4 & 5: Data Ingestion – Backfill & Incremental Loading

## Overview

**Phase 4** loads all GitHub events from the past 7 days to establish initial data.  
**Phase 5** loads the latest hourly file, suitable for scheduling every hour.

Together, these phases implement the complete ingestion pipeline:
- **Backfill** (Phase 4): Historical data (one-time, ~30-45 minutes)
- **Incremental** (Phase 5): New data (every hour, ~10-15 seconds)

---

## Phase 4: Initial 7-Day Backfill

### Purpose

Load all GitHub events from the past 7 days to bootstrap the data warehouse.

**Scope**:
- Days: Past 7 days (automatically calculated)
- Files: 7 days × 24 hours = 168 hourly files
- Events: ~2-2.5 million (approximately)
- Runtime: 30-45 minutes (network dependent)

### Script: `ingestion/backfill/load_last_7_days.py`

```bash
cd c:\Users\abdul\Basith-Saas\DE\github-analytics-pipeline
python ingestion/backfill/load_last_7_days.py
```

### Workflow

```
START
  ↓
Generate file list (past 7 days, all 24 hours)
  ↓
For each file (168 total):
  ├─ Check if already loaded (skip if yes)
  ├─ Download from GH Archive
  ├─ Parse NDJSON (newline-delimited JSON)
  ├─ Validate event structure
  ├─ Load into RAW.GITHUB_EVENTS
  ├─ Record in RAW.LOAD_HISTORY
  └─ Log results
  ↓
Print summary statistics
  ↓
Validate results in Snowflake
  ↓
COMPLETE (success or failure)
```

### Class: BackfillProcessor

```python
processor = BackfillProcessor(days=7)
success = processor.run()
processor.close()
```

**Methods**:
- `generate_file_list()` → List of (date, hour) tuples
- `process_file(date, hour)` → (success, row_count, message)
- `run()` → Complete execution with error handling
- `print_summary()` → Statistics and results
- `close()` → Clean up connections

### Expected Output

```
╔══════════════════════════════════════════════════════════╗
║  GitHub Analytics Pipeline - 7-Day Backfill Started     ║
╚══════════════════════════════════════════════════════════╝

Generated list of 168 files to load
Starting backfill of 168 files...

[1/168] Processing: 2024-01-08-0
↓ Downloading: 2024-01-08-0.json.gz
↑ Loading 9876 events from 2024-01-08-0.json.gz
✓ Success: 2024-01-08-0.json.gz (9876 rows)

[2/168] Processing: 2024-01-08-1
↓ Downloading: 2024-01-08-1.json.gz
↑ Loading 10234 events from 2024-01-08-1.json.gz
✓ Success: 2024-01-08-1.json.gz (10234 rows)

... (164 more files) ...

╔══════════════════════════════════════════════════════════╗
║  Backfill Summary                                        ║
╚══════════════════════════════════════════════════════════╝

Total Files:           168
Files Downloaded:      168
Files Skipped:           0
Files Failed:            0

Total Events Loaded:   2,456,789
Duration:            1847s (30.8m)
Avg per file:          11.0s

Status:                ✓ SUCCESS

==== Validating Backfill Results ====
Total events in RAW.GITHUB_EVENTS: 2,456,789
Successful loads in LOAD_HISTORY: 168
Failed loads in LOAD_HISTORY: 0
Date range: 2024-01-08 to 2024-01-15

✓ Validation PASSED - Backfill completed successfully

🎉 Backfill completed successfully!
📊 Proceed to Phase 5: Incremental Hourly Loading
```

### Error Handling

**Retries**: Automatic retry with exponential backoff (3 attempts, 5-10 seconds delay)

**Failed Files**: Recorded in LOAD_HISTORY with error details, can be retried

**Network Issues**: 
- Timeout: 30 seconds per request
- Retry with increasing delays
- Continues processing other files

**Data Validation**:
- Skip invalid events (log count)
- Continue with valid events
- Report summary at end

### Validation Queries

After backfill completes:

```sql
-- Row count
SELECT COUNT(*) FROM RAW.GITHUB_EVENTS;
-- Expected: ~2.5M rows

-- Files loaded
SELECT COUNT(*) FROM RAW.LOAD_HISTORY WHERE STATUS = 'SUCCESS';
-- Expected: 168 rows

-- Date range
SELECT MIN(RAW_DATA:created_at), MAX(RAW_DATA:created_at) FROM RAW.GITHUB_EVENTS;
-- Expected: Last 7 days

-- Event type distribution
SELECT RAW_DATA:type, COUNT(*) 
FROM RAW.GITHUB_EVENTS 
GROUP BY RAW_DATA:type 
ORDER BY COUNT(*) DESC;
```

### Troubleshooting Phase 4

**Issue**: Script fails early (e.g., file 1-10)

**Solutions**:
- Check Snowflake connection: `python test_ingestion_setup.py`
- Verify .env has correct credentials
- Check warehouse is running: `USE WAREHOUSE COMPUTE_WH`

**Issue**: Script times out (>1 hour)

**Solutions**:
- Check network speed
- Increase warehouse size temporarily
- Run in background: Use Windows Task Scheduler

**Issue**: Some files fail to load

**Solutions**:
- Check logs in `logs/ingestion.log`
- Re-run script (skips already loaded files)
- Query LOAD_HISTORY for specific failures

---

## Phase 5: Incremental Hourly Loading

### Purpose

Load the latest available GH Archive file every hour. Designed for production scheduling.

### Script: `ingestion/incremental/load_latest_hour.py`

```bash
python ingestion/incremental/load_latest_hour.py
```

### Workflow

```
START
  ↓
Determine latest available file
  ↓
Check if already loaded
  ├─ If yes: Log and exit (skipped)
  └─ If no: Continue
  ↓
Download file from GH Archive
  ↓
Validate and load events
  ↓
Record in LOAD_HISTORY
  ↓
COMPLETE (success or skipped)
```

### Class: IncrementalLoader

```python
loader = IncrementalLoader(look_back_hours=2)
success, message, row_count = loader.process()
loader.close()
```

**Methods**:
- `get_latest_file_to_load()` → (file_name, date, hour) or None
- `process()` → (success, message, row_count)
- `close()` → Clean up connections

### Expected Output

```
GitHub Analytics Pipeline - Incremental Load
Execution time: 2024-01-15 11:05:00+00:00

======================================================================
Incremental Load Started
======================================================================

Checking for new files (look_back_hours=2)
Latest available file: 2024-01-15-10.json.gz
New file found: 2024-01-15-10.json.gz

↓ Downloading: 2024-01-15-10.json.gz
Download 2024-01-15-10.json.gz completed in 3.45 seconds

↑ Loading 10456 events from 2024-01-15-10.json.gz
Load 2024-01-15-10.json.gz completed in 8.23 seconds

Recorded load: 2024-01-15-10.json.gz (10456 rows, 0.00s)
✓ Load 2024-01-15-10.json.gz in 8.23s

======================================================================
Incremental Load Summary
======================================================================

Status: ✓ SUCCESS
Message: ✓ Loaded 10456 events from 2024-01-15-10.json.gz
Rows Loaded: 10,456
```

### Scheduling Phase 5

#### Option A: Windows Task Scheduler

1. Create batch file: `scheduler/run_incremental_load.bat`
   ```batch
   @echo off
   cd C:\Users\abdul\Basith-Saas\DE\github-analytics-pipeline
   venv\Scripts\activate
   python ingestion/incremental/load_latest_hour.py
   ```

2. Open Task Scheduler
3. Create Basic Task:
   - **Name**: Load GitHub Events Hourly
   - **Trigger**: Daily, repeat every 1 hour
   - **Action**: Run program: `run_incremental_load.bat`

#### Option B: Cron (Linux/WSL)

```bash
# Add to crontab
5 * * * * cd /path/to/pipeline && python ingestion/incremental/load_latest_hour.py >> logs/cron.log 2>&1
```

#### Option C: Apache Airflow (Phase 14)

```python
# In Airflow DAG
from airflow import DAG
from airflow.operators.bash import BashOperator

load_latest_hour_task = BashOperator(
    task_id='load_latest_hour',
    bash_command='cd /path/to/pipeline && python ingestion/incremental/load_latest_hour.py',
    dag=dag
)
```

### Exit Codes

- **0**: Success (new file loaded) or file already loaded
- **1**: Error (check logs)
- **2**: Fatal error (critical issue)

### Monitoring

Check load status:

```sql
-- Last 10 loads
SELECT FILE_NAME, LOAD_TS, STATUS, ROW_COUNT
FROM RAW.LOAD_HISTORY
ORDER BY LOAD_TS DESC
LIMIT 10;

-- Data freshness
SELECT MAX(FILE_HOUR) AS latest, 
       DATEDIFF('minute', MAX(FILE_HOUR), CURRENT_TIMESTAMP()) AS minutes_behind
FROM RAW.LOAD_HISTORY
WHERE STATUS = 'SUCCESS';
```

---

## Performance Metrics

### Phase 4 Backfill

| Metric | Value |
|--------|-------|
| Total Files | 168 |
| Total Events | ~2.5M |
| Duration | 30-45 minutes |
| Per File | 10-15 seconds |
| Network | 0.5-2 MB/s |
| Snowflake Insert | 1000-2000 rows/sec |

### Phase 5 Incremental

| Metric | Value |
|--------|-------|
| Files per run | 1 |
| Events per hour | ~10K |
| Duration | 5-15 seconds |
| Network | 0.5-2 MB/s |
| Snowflake Insert | 1000-2000 rows/sec |

---

## Data Quality Monitoring

### During Backfill

```python
# In process_file():
events = client.download_events(date, hour, validate=True)
# Validates:
# - Not null: id, type, actor, repo, created_at
# - Proper structure
# - Valid JSON
```

### After Load

```sql
-- Check for nulls
SELECT SUM(CASE WHEN RAW_DATA:id IS NULL THEN 1 ELSE 0 END) as null_ids
FROM RAW.GITHUB_EVENTS;

-- Check date range
SELECT MIN(RAW_DATA:created_at), MAX(RAW_DATA:created_at) 
FROM RAW.GITHUB_EVENTS;

-- Event type distribution
SELECT RAW_DATA:type, COUNT(*) as count
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:type
ORDER BY count DESC;
```

---

## Integration with Later Phases

These scripts are standalone but integrate seamlessly:

- **Phase 6**: Analyze raw data with SQL queries
- **Phase 7-9**: Transform with dbt (sources built on RAW tables)
- **Phase 14**: Schedule with Airflow

The raw data will be transformed in Phase 8 (staging) and Phase 9 (marts).

---

## Files Summary

```
ingestion/
├── backfill/
│   └── load_last_7_days.py      ← Phase 4
├── incremental/
│   └── load_latest_hour.py      ← Phase 5
└── utils/
    ├── gharchive_client.py      (Phase 3)
    ├── snowflake_loader.py      (Phase 3)
    └── helpers.py               (Phase 3)

logs/
├── pipeline.log                 ← All messages
├── ingestion.log                ← Ingestion-specific
└── snowflake.log                ← Database queries
```

---

## Next Steps

1. Run Phase 4: `python ingestion/backfill/load_last_7_days.py`
2. Verify data: Run validation queries above
3. Test Phase 5: `python ingestion/incremental/load_latest_hour.py`
4. Proceed to **Phase 6: Raw Data Analysis Queries**

---

**Status**: ✅ Complete  
**Phases**: 4 & 5 of 15  
**Next Phase**: Phase 6 - Raw Data Analysis