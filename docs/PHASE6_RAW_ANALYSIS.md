# Phase 6: Raw Data Analysis – Complete Guide

## Overview

Phase 6 analyzes the raw GitHub events data loaded in Phase 4 to:
- Validate data quality and completeness
- Understand event type distribution
- Identify most active repositories and developers
- Detect data anomalies
- Monitor load performance
- Establish baseline metrics for transformation phases

---

## Analysis Queries

All queries run against `GITHUB_DBT.RAW` schema after backfill completes.

### 1. Data Completeness Check

**Purpose**: Verify all required fields are present and valid

```sql
-- Overall statistics
SELECT 
  COUNT(*) as total_events,
  COUNT(DISTINCT RAW_DATA:id) as distinct_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repositories,
  MIN(RAW_DATA:created_at) as earliest_event,
  MAX(RAW_DATA:created_at) as latest_event,
  DATEDIFF('day', MIN(RAW_DATA:created_at), MAX(RAW_DATA:created_at)) as days_of_data
FROM GITHUB_EVENTS;
```

**Expected Results** (after 7-day backfill):
```
total_events:         ~2,500,000
distinct_events:      ~2,500,000
unique_actors:        ~100,000
unique_repositories:  ~150,000
days_of_data:         7
```

### 2. Event Type Distribution

**File**: `sql/analysis/event_type_distribution.sql`

**Purpose**: Break down events by type

```sql
SELECT 
  RAW_DATA:type as event_type,
  COUNT(*) as event_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percent_of_total,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repos
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:type
ORDER BY event_count DESC;
```

**Sample Output**:
```
event_type          | count   | percent | actors | repos
--------------------|---------|---------|--------|-------
PushEvent           | 800,000 | 32.0%   | 50,000 | 80,000
PullRequestEvent    | 400,000 | 16.0%   | 30,000 | 40,000
IssuesEvent         | 350,000 | 14.0%   | 25,000 | 35,000
WatchEvent          | 300,000 | 12.0%   | 20,000 | 30,000
IssueCommentEvent   | 250,000 | 10.0%   | 15,000 | 25,000
CreateEvent         | 200,000 | 8.0%    | 10,000 | 20,000
DeleteEvent         | 150,000 | 6.0%    | 8,000  | 15,000
ForkEvent           | 50,000  | 2.0%    | 5,000  | 10,000
```

### 3. Top Repositories

**File**: `sql/analysis/top_repositories.sql`

**Purpose**: Identify most active repositories

```sql
SELECT 
  RAW_DATA:repo:id as repo_id,
  RAW_DATA:repo:name as repo_name,
  COUNT(*) as total_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_contributors,
  COUNT(DISTINCT RAW_DATA:type) as event_type_count
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:repo:id, RAW_DATA:repo:name
ORDER BY total_events DESC
LIMIT 50;
```

**Sample Output**:
```
repo_id    | repo_name                      | events | contributors | types
-----------|--------------------------------|--------|--------------|------
1296269    | torvalds/linux                 | 8,500  | 2,000        | 7
123456     | tensorflow/tensorflow          | 7,200  | 1,800        | 7
234567     | kubernetes/kubernetes          | 6,900  | 1,600        | 6
345678     | facebook/react                 | 5,800  | 1,400        | 6
456789     | microsoft/vscode               | 5,500  | 1,200        | 6
```

### 4. Top Developers

**File**: `sql/analysis/top_developers.sql`

**Purpose**: Identify most active developers/bots

```sql
SELECT 
  RAW_DATA:actor:id as actor_id,
  RAW_DATA:actor:login as actor_login,
  RAW_DATA:actor:type as actor_type,
  COUNT(*) as total_events,
  COUNT(DISTINCT RAW_DATA:repo:id) as repositories_contributed_to,
  COUNT(DISTINCT RAW_DATA:type) as event_types
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:actor:id, RAW_DATA:actor:login, RAW_DATA:actor:type
ORDER BY total_events DESC
LIMIT 50;
```

**Sample Output**:
```
actor_id | actor_login        | type | events | repos | types
---------|-------------------|------|--------|-------|-------
1234567  | dependabot[bot]    | Bot  | 12,000 | 5,000 | 1
2345678  | github-actions     | Bot  | 10,500 | 4,200 | 1
3456789  | john-doe           | User | 850    | 120   | 5
4567890  | jane-smith         | User | 720    | 105   | 5
5678901  | contributor-bot    | Bot  | 650    | 200   | 2
```

### 5. Daily Activity Trends

**File**: `sql/analysis/daily_activity.sql`

**Purpose**: Identify patterns and anomalies in daily activity

```sql
SELECT 
  DATE(RAW_DATA:created_at) as activity_date,
  COUNT(*) as daily_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_developers,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repositories,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  ROUND(COUNT(*) / 24.0, 0) as avg_events_per_hour
FROM RAW.GITHUB_EVENTS
GROUP BY DATE(RAW_DATA:created_at)
ORDER BY activity_date DESC;
```

**Sample Output**:
```
date       | events  | developers | repos | types | hourly_avg
-----------|---------|------------|-------|-------|----------
2024-01-15 | 385,000 | 85,000     | 120,000 | 7 | 16,042
2024-01-14 | 355,000 | 80,000     | 115,000 | 7 | 14,792
2024-01-13 | 340,000 | 78,000     | 110,000 | 7 | 14,167
2024-01-12 | 365,000 | 82,000     | 118,000 | 7 | 15,208
```

---

## Data Quality Checks

### Null Value Analysis

```sql
SELECT 
  'id' as field,
  COUNT(CASE WHEN RAW_DATA:id IS NULL THEN 1 END) as null_count
FROM GITHUB_EVENTS
-- Repeat for other fields: type, actor, repo, created_at
```

**Expected Results**: All critical fields should have 0 nulls

### Duplicate Detection

```sql
SELECT 
  RAW_DATA:id,
  COUNT(*) as occurrence_count
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:id
HAVING COUNT(*) > 1;
```

**Expected Results**: Should return 0 rows (no duplicates)

### Date Range Validation

```sql
SELECT 
  MIN(RAW_DATA:created_at) as earliest,
  MAX(RAW_DATA:created_at) as latest,
  DATEDIFF('day', MIN(RAW_DATA:created_at), MAX(RAW_DATA:created_at)) as days_spanned
FROM RAW.GITHUB_EVENTS;
```

**Expected Results**: Should span 7 days

---

## File Organization

```
sql/analysis/
├── raw_data_analysis.sql         ← Comprehensive analysis
├── event_type_distribution.sql   ← Event type breakdown
├── top_repositories.sql          ← Top 50 repositories
├── top_developers.sql            ← Top 50 developers
└── daily_activity.sql            ← Daily trends
```

---

## Execution Steps

### Step 1: Run Comprehensive Analysis

```bash
# Using Snowflake Web UI:
# 1. Copy contents of sql/analysis/raw_data_analysis.sql
# 2. Paste into Snowflake editor
# 3. Execute all queries

# Or using SnowSQL:
snowsql -a xy12345 -u username -f sql/analysis/raw_data_analysis.sql
```

### Step 2: Examine Key Metrics

```sql
-- Quick health check
SELECT COUNT(*) as total_events FROM RAW.GITHUB_EVENTS;
SELECT COUNT(*) as successful_loads FROM RAW.LOAD_HISTORY WHERE STATUS = 'SUCCESS';
SELECT COUNT(DISTINCT RAW_DATA:type) as event_types FROM RAW.GITHUB_EVENTS;
```

### Step 3: Run Individual Analysis Queries

```sql
-- Event distribution
SELECT * FROM sql/analysis/event_type_distribution.sql;

-- Top repositories
SELECT * FROM sql/analysis/top_repositories.sql;

-- Top developers
SELECT * FROM sql/analysis/top_developers.sql;

-- Daily activity
SELECT * FROM sql/analysis/daily_activity.sql;
```

### Step 4: Document Findings

Note key metrics in `docs/project_notes.md`:
- Total events loaded
- Date range covered
- Most common event types
- Top repositories
- Top developers
- Data anomalies (if any)

---

## Expected Findings

### Normal Patterns
- ✓ PushEvent is most common (~30% of events)
- ✓ Large projects (kubernetes, tensorflow) have most activity
- ✓ Bots (dependabot, github-actions) are top contributors
- ✓ Daily variations exist but trend is consistent
- ✓ All critical fields are populated

### Potential Issues to Watch
- ✗ Missing or null values in key fields
- ✗ Duplicate events with same ID
- ✗ Files with unusually low event counts
- ✗ Data gaps (missing hours)
- ✗ Events with dates in the future

---

## Insights for Transformation

Phase 6 findings inform later phases:

**Phase 7-9 (dbt)**: 
- Dimension cardinality (actors, repositories)
- Fact grain (events vs. pushes)
- Aggregation levels

**Phase 13 (Power BI)**:
- KPI baselines
- Dashboard filters
- Drill-down dimensions

**Phase 14 (Airflow)**:
- Data quality thresholds
- Alert conditions
- SLA targets

---

## Performance Tuning

If queries run slowly:

```sql
-- Add clustering hints
ALTER TABLE RAW.GITHUB_EVENTS 
  CLUSTER BY (LOAD_TS, RAW_DATA:type);

-- Create materialized views for frequent queries
CREATE MATERIALIZED VIEW EVENT_SUMMARY AS
SELECT 
  RAW_DATA:type,
  COUNT(*) as count
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:type;
```

---

## Next Steps

1. ✓ Execute all analysis queries
2. ✓ Document findings in project_notes.md
3. → **Phase 7**: Initialize dbt project
4. → **Phase 8**: Create staging models (transform raw data)
5. → **Phase 9**: Build dimensional models

---

**Status**: ✅ Complete  
**Phase**: 6 of 15  
**Next Phase**: Phase 7 - dbt Foundation Setup