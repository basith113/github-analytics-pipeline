# Phase 2: Snowflake Foundation – Complete Setup Guide

## Overview

Phase 2 establishes the Snowflake data warehouse foundation with three schemas:
- **RAW**: Stores unprocessed GitHub events
- **STAGING**: Cleaned and flattened data
- **MARTS**: Analytics-ready dimensional and fact tables

---

## Architecture

```
GITHUB_DBT Database
├── RAW Schema (Raw data layer)
│   ├── GITHUB_EVENTS (variant JSON storage)
│   ├── LOAD_HISTORY (deduplication tracking)
│   └── Monitoring Views
│
├── STAGING Schema (Transformation layer)
│   └── (Models created in Phase 8)
│
└── MARTS Schema (Analytics layer)
    └── (Dimensions & facts created in Phase 9)
```

---

## Files Created

### 1. SQL DDL Scripts

#### `sql/ddl/create_database.sql`
Creates the main GITHUB_DBT database and all three schemas.

**What it does**:
- Creates `GITHUB_DBT` database with 1-day retention
- Creates `RAW` schema for raw data
- Creates `STAGING` schema for transformations
- Creates `MARTS` schema for analytics

**When to run**: First, before any other scripts

#### `sql/ddl/create_raw_tables.sql`
Creates the core raw tables and monitoring views.

**What it does**:
- Creates `GITHUB_EVENTS` table (stores raw JSON)
- Creates `LOAD_HISTORY` table (tracks loaded files)
- Creates monitoring views (recent loads, failures, daily summary)
- Configures clustering for performance

**When to run**: After create_database.sql

#### `sql/ddl/create_load_history.sql`
Creates utility procedures and advanced monitoring queries.

**What it does**:
- Stored procedures for recording loads/failures
- Advanced monitoring queries (missing hours, anomalies)
- Views for Python integration
- Cleanup procedures

**When to run**: After create_raw_tables.sql (optional)

### 2. Validation Scripts

#### `sql/validation/snowflake_setup_validation.sql`
Comprehensive verification that all setup is correct.

**What it checks**:
- Database and schemas exist
- All tables created correctly
- All views created
- All procedures created
- User has proper permissions
- Tables are empty and ready

**When to run**: After all DDL scripts

---

## Execution Steps

### Step 1: Prerequisites

```bash
# ✓ Snowflake account configured in .env
# ✓ COMPUTE_WH warehouse exists
# ✓ You have ACCOUNTADMIN role
```

### Step 2: Connect to Snowflake

Use Snowflake Web UI or SnowSQL:

```bash
# Option A: SnowSQL (command line)
snowsql -a xy12345 -u your_username

# Option B: Snowflake Web UI (https://xy12345.snowflakecomputing.com)
```

### Step 3: Execute DDL Scripts (In Order)

#### Script 1: Create Database & Schemas

```sql
-- Copy and paste contents of sql/ddl/create_database.sql
-- Or upload file and execute

-- Expected output:
-- ✓ Database GITHUB_DBT created
-- ✓ Schema RAW created
-- ✓ Schema STAGING created
-- ✓ Schema MARTS created
```

**Verification**:
```sql
SHOW DATABASES LIKE 'GITHUB_DBT';
SHOW SCHEMAS IN DATABASE GITHUB_DBT;
```

#### Script 2: Create Raw Tables

```sql
-- Copy and paste contents of sql/ddl/create_raw_tables.sql

-- Expected output:
-- ✓ Table GITHUB_EVENTS created
-- ✓ Table LOAD_HISTORY created
-- ✓ Views created (LOAD_HISTORY_RECENT, etc.)
-- ✓ Procedures created
```

**Verification**:
```sql
USE DATABASE GITHUB_DBT;
USE SCHEMA RAW;
SHOW TABLES;
SHOW VIEWS;
```

#### Script 3: Create Load History Utilities (Optional)

```sql
-- Copy and paste contents of sql/ddl/create_load_history.sql

-- Expected output:
-- ✓ Procedures created
-- ✓ Views created for Python integration
```

### Step 4: Validate Setup

```sql
-- Copy and paste contents of sql/validation/snowflake_setup_validation.sql

-- Expected output: All checks should show ✓ PASS
```

---

## Table Schemas

### GITHUB_EVENTS

Stores raw GitHub events as JSON.

```sql
DESC TABLE RAW.GITHUB_EVENTS;
```

| Column | Type | Description |
|--------|------|-------------|
| RAW_DATA | VARIANT | Full JSON event from GH Archive |
| FILE_NAME | VARCHAR(50) | Source file name (YYYY-MM-DD-H.json.gz) |
| LOAD_TS | TIMESTAMP_NTZ | When row was loaded |
| _INSERTED_AT | TIMESTAMP_NTZ | System insertion timestamp |
| _FILE_ROW_NUMBER | INT | Row number within file |

**Sample Query**:
```sql
-- View raw event structure
SELECT RAW_DATA FROM RAW.GITHUB_EVENTS LIMIT 1;

-- Extract specific fields
SELECT 
  RAW_DATA:id AS event_id,
  RAW_DATA:type AS event_type,
  RAW_DATA:actor.login AS actor_login,
  RAW_DATA:created_at AS created_at
FROM RAW.GITHUB_EVENTS
LIMIT 10;
```

### LOAD_HISTORY

Tracks which files have been loaded (deduplication).

```sql
DESC TABLE RAW.LOAD_HISTORY;
```

| Column | Type | Description |
|--------|------|-------------|
| FILE_NAME | VARCHAR(50) | File identifier (PK) |
| LOAD_TS | TIMESTAMP_NTZ | When file was loaded |
| FILE_HOUR | TIMESTAMP_NTZ | Hour represented by file |
| ROW_COUNT | INT | Number of events in file |
| FILE_SIZE_BYTES | INT | Size of compressed file |
| STATUS | VARCHAR(20) | SUCCESS, FAILED, SKIPPED, RETRY |
| ERROR_MESSAGE | VARCHAR(1000) | Error details if failed |
| RETRY_COUNT | INT | Number of retry attempts |
| LOAD_DURATION_SECONDS | DECIMAL(10,2) | Time to load file |
| LOADED_BY | VARCHAR(255) | User/process that loaded |

**Sample Queries**:
```sql
-- Check load history
SELECT * FROM RAW.LOAD_HISTORY ORDER BY LOAD_TS DESC LIMIT 10;

-- Summary statistics
SELECT 
  STATUS,
  COUNT(*) AS count,
  SUM(ROW_COUNT) AS total_rows
FROM RAW.LOAD_HISTORY
GROUP BY STATUS;

-- Recent loads
SELECT * FROM RAW.LOAD_HISTORY_RECENT;

-- Load failures
SELECT * FROM RAW.LOAD_HISTORY_FAILURES;
```

---

## Monitoring Views

### LOAD_HISTORY_RECENT
Recently loaded files (past 7 days)

```sql
SELECT * FROM RAW.LOAD_HISTORY_RECENT LIMIT 5;
```

### LOAD_HISTORY_FAILURES
Failed load attempts for investigation

```sql
SELECT * FROM RAW.LOAD_HISTORY_FAILURES;
```

### LOAD_HISTORY_DAILY_SUMMARY
Daily aggregated statistics

```sql
SELECT * FROM RAW.LOAD_HISTORY_DAILY_SUMMARY;
```

---

## Stored Procedures

### CHECK_FILE_LOADED
Check if a file has already been loaded

```sql
CALL CHECK_FILE_LOADED('2024-01-15-3.json.gz');
```

### RECORD_FILE_LOAD
Record a successful file load (called by Python)

```sql
CALL RECORD_FILE_LOAD(
  '2024-01-15-3.json.gz',
  '2024-01-15 03:00:00'::TIMESTAMP_NTZ,
  10234,
  45.5
);
```

### RECORD_FILE_LOAD_FAILURE
Record a failed load attempt

```sql
CALL RECORD_FILE_LOAD_FAILURE(
  '2024-01-15-3.json.gz',
  '2024-01-15 03:00:00'::TIMESTAMP_NTZ,
  'Connection timeout after 30 seconds'
);
```

---

## Data Retention Settings

| Layer | Retention | Purpose |
|-------|-----------|---------|
| RAW | 1 day | Fast discovery of recent issues |
| STAGING | 1 day | Minimal storage for intermediate data |
| MARTS | 7 days | Longer retention for analytics |

To modify:
```sql
ALTER SCHEMA RAW SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

---

## Verification Checklist

After running all scripts, verify:

- [ ] Database `GITHUB_DBT` exists
- [ ] Schemas `RAW`, `STAGING`, `MARTS` exist
- [ ] Table `GITHUB_EVENTS` exists with VARIANT column
- [ ] Table `LOAD_HISTORY` exists with proper columns
- [ ] Views `LOAD_HISTORY_RECENT`, etc. exist
- [ ] Procedures `CHECK_FILE_LOADED`, etc. exist
- [ ] Both tables are empty (0 rows)
- [ ] User has proper permissions

Run validation:
```sql
-- From sql/validation/snowflake_setup_validation.sql
```

---

## Common Queries for Monitoring

### Get current data volume
```sql
SELECT 
  SUM(ROW_COUNT) AS total_events,
  COUNT(*) AS files_loaded,
  MAX(LOAD_TS) AS last_load_time
FROM RAW.LOAD_HISTORY
WHERE STATUS = 'SUCCESS';
```

### Check for load failures
```sql
SELECT 
  FILE_NAME,
  ERROR_MESSAGE,
  LOAD_TS
FROM RAW.LOAD_HISTORY
WHERE STATUS = 'FAILED'
ORDER BY LOAD_TS DESC;
```

### Data freshness
```sql
SELECT 
  MAX(FILE_HOUR) AS latest_data,
  DATEDIFF('hour', MAX(FILE_HOUR), CURRENT_TIMESTAMP()) AS hours_behind
FROM RAW.LOAD_HISTORY
WHERE STATUS = 'SUCCESS';
```

---

## Troubleshooting

### Issue: "Table does not exist" error

**Solution**: Ensure you're using the correct database and schema
```sql
USE DATABASE GITHUB_DBT;
USE SCHEMA RAW;
SHOW TABLES;
```

### Issue: "Insufficient privileges" error

**Solution**: Ensure you have ACCOUNTADMIN role
```sql
SELECT CURRENT_ROLE();
```

### Issue: Warehouse not found

**Solution**: Create or use existing warehouse
```sql
CREATE WAREHOUSE COMPUTE_WH 
  WITH WAREHOUSE_SIZE = 'XSMALL' 
  AUTO_SUSPEND = 5 
  AUTO_RESUME = TRUE;
```

---

## Next Steps

Once Phase 2 is validated:

1. **Phase 3**: Create Python ingestion utilities
2. **Phase 4**: Load first 7 days of data
3. **Phase 5**: Set up incremental hourly loads
4. **Phase 6**: Analyze raw data quality
5. **Phase 7**: Initialize dbt project

---

## Files Summary

```
sql/
├── ddl/
│   ├── create_database.sql          ← Run first
│   ├── create_raw_tables.sql        ← Run second
│   └── create_load_history.sql      ← Run third (optional)
└── validation/
    └── snowflake_setup_validation.sql  ← Run last to verify
```

---

**Status**: ✅ Complete  
**Phase**: 2 of 15  
**Next Phase**: Phase 3 - GH Archive Ingestion Utilities