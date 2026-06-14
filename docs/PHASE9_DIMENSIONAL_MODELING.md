# Phase 9: Dimensional Modeling – Complete Guide

## Overview

Phase 9 implements the star schema with three dimension tables (actor, repository, event_type) and one fact table (events).

**Components**:
- 3 Snowflake dimension tables (slowly changing & reference)
- 1 fact table with grain of one event
- Surrogate keys with dbt_utils
- Foreign key relationships
- Comprehensive testing

**Architecture**:
```
    dim_actor
       ↑
       │
   fact_events ←─── dim_event_type
       ↓
       └─ dim_repository
```

---

## Dimensional Model Design

### Star Schema Overview

```
┌─────────────────────────────────────────┐
│              fact_events                │
│ (2.5M rows, grain: one per event)      │
├─────────────────────────────────────────┤
│ event_key (PK)                          │
│ event_id (unique, natural key)          │
│ actor_key (FK → dim_actor)              │
│ repo_key (FK → dim_repository)          │
│ event_type_key (FK → dim_event_type)    │
│ created_at, event_date, event_hour...   │
└─────────────────────────────────────────┘
    │              │              │
    │              │              └──────────────────┐
    │              └───────────────┐                 │
    │                              │                 │
    ↓                              ↓                 ↓
┌──────────────┐  ┌────────────────────┐  ┌──────────────────┐
│  dim_actor   │  │ dim_event_type     │  │ dim_repository   │
├──────────────┤  ├────────────────────┤  ├──────────────────┤
│ actor_key    │  │ event_type_key     │  │ repo_key         │
│ actor_id     │  │ event_type         │  │ repo_id          │
│ actor_login  │  │ event_category     │  │ repo_name        │
│ actor_type   │  │ event_description  │  │ repo_owner       │
│ is_bot       │  │ percent_of_total   │  │ repo_short_name  │
│ (100K rows)  │  │ (11 rows)          │  │ is_test_repo     │
└──────────────┘  └────────────────────┘  │ (150K rows)      │
  SCD Type 2          Type 1 (static)     └──────────────────┘
                                             Type 1 (static)
```

---

## Dimension Tables

### 1. dim_actor – SCD Type 2

**Purpose**: Track user/bot attributes with history

**Grain**: One row per actor (with SCD Type 2, could have multiple rows per actor_id over time)

**Slowly Changing Dimension**:
- `dbt_valid_from`: When record became effective
- `dbt_valid_to`: When record is no longer valid (2099-12-31 for current)
- `dbt_is_current`: Boolean flag for active records

**Example Data**:
```
actor_key | actor_id | actor_login | actor_type | is_bot | valid_from | valid_to   | is_current
----------|----------|-------------|------------|--------|------------|------------|----------
abc123    | 1234567  | john-doe    | User       | false  | 2024-01-08 | 2099-12-31 | true
def456    | 2345678  | bot-action  | Bot        | true   | 2024-01-08 | 2099-12-31 | true
```

**Usage**: Connect from fact_events via actor_key for actor details

### 2. dim_repository – Type 1 SCD

**Purpose**: Static reference for repositories

**Grain**: One row per repository (no history tracking)

**Columns**: repo_id, repo_name, repo_owner, repo_short_name, is_test_repo, first_event_at, last_event_at

**Example Data**:
```
repo_key | repo_id | repo_name            | repo_owner  | repo_short_name | is_test_repo
---------|---------|----------------------|-------------|-----------------|----------
xyz789   | 1296269 | torvalds/linux       | torvalds    | linux           | false
uvw012   | 123456  | tensorflow/tensorflow| tensorflow  | tensorflow      | false
```

**Usage**: Connect from fact_events via repo_key for repository details

### 3. dim_event_type – Type 1 SCD

**Purpose**: Static enumeration of event types

**Grain**: One row per GitHub event type (11 types)

**Columns**: event_type, event_description, event_category, event_count, percent_of_total_events

**Event Categories**:
- **Activity**: PushEvent, PullRequestEvent, IssuesEvent
- **Repository Management**: CreateEvent, DeleteEvent
- **Engagement**: WatchEvent, ForkEvent
- **Collaboration**: MemberEvent, ReleaseEvent, PullRequestReviewEvent

**Example Data**:
```
event_type_key | event_type       | event_description          | category           | percent
---------------|------------------|----------------------------|--------------------|--------
key1           | PushEvent        | Code push to repository    | Activity           | 32.0%
key2           | PullRequestEvent | PR opened/closed/reopened  | Activity           | 16.0%
key3           | WatchEvent       | User starred repository    | Engagement         | 12.0%
```

**Usage**: Connect from fact_events via event_type_key for event details

---

## Fact Table

### fact_events – Transaction Grain

**Purpose**: Record of every GitHub event with fact and dimension relationships

**Grain**: One row per GitHub event

**Volume**: ~2.5M from 7-day backfill, ~10K/hour incremental

**Keys**:
- **Surrogate Key**: event_key (UUID, dbt-generated)
- **Natural Key**: event_id (unique identifier)
- **Foreign Keys**: actor_key → dim_actor, repo_key → dim_repository, event_type_key → dim_event_type

**Fact Columns** (quantitative measures):
- None in this case (pure transaction log)

**Dimension Columns** (for denormalization & query performance):
- event_type, actor_id, actor_login, repo_id, repo_name

**Time Dimensions** (extracted from created_at):
- event_date, event_hour, event_day_of_week, event_week, event_month, event_year

**Example Data**:
```
event_key | event_id | actor_key | repo_key | event_type_key | event_type   | event_date | event_hour
----------|----------|-----------|----------|----------------|--------------|------------|----------
evt1      | ev123    | abc123    | xyz789   | key1           | PushEvent    | 2024-01-15 | 14
evt2      | ev124    | def456    | uvw012   | key2           | PullRequest  | 2024-01-15 | 15
```

---

## Surrogate Keys

Using `dbt_utils.generate_surrogate_key()`:

```sql
{{ dbt_utils.generate_surrogate_key(['actor_id']) }} as actor_key
{{ dbt_utils.generate_surrogate_key(['repo_id']) }} as repo_key
{{ dbt_utils.generate_surrogate_key(['event_type']) }} as event_type_key
{{ dbt_utils.generate_surrogate_key(['event_id']) }} as event_key
```

**Benefits**:
- Short, efficient keys for joins
- Consistent across runs
- Decouples data structure from business keys

---

## Execution Steps

### Step 1: Install dbt_utils

```bash
cd dbt/github_dbt

# Add to packages.yml (create if not exists)
# packages:
#   - package: dbt-labs/dbt_utils
#     version: 1.1.1

dbt deps
```

### Step 2: Run Dimension Models

```bash
# Run all mart models
dbt run --models marts

# Or run individually
dbt run --models dim_actor
dbt run --models dim_repository
dbt run --models dim_event_type
```

**Expected Output**:
```
Executing node: dim_actor
  create table GITHUB_DBT.MARTS.DIM_ACTOR
✓ created in 28.5s

Executing node: dim_repository
  create table GITHUB_DBT.MARTS.DIM_REPOSITORY
✓ created in 35.2s

Executing node: dim_event_type
  create table GITHUB_DBT.MARTS.DIM_EVENT_TYPE
✓ created in 8.3s

Done! 3 models created in 72.0s
```

### Step 3: Run Fact Table

```bash
dbt run --models fact_events
```

**Expected Output**:
```
Executing node: fact_events
  create table GITHUB_DBT.MARTS.FACT_EVENTS
✓ created in 145.2s (2.5M rows inserted)

Done! 1 model created in 145.2s
```

### Step 4: Run All Tests

```bash
dbt test --models marts
```

**Expected Output**:
```
Running tests...

stg_actors_actor_id_not_null: PASS
stg_actors_actor_id_unique: PASS
dim_actor_actor_key_not_null: PASS
dim_actor_actor_key_unique: PASS
...
fact_events_actor_key_relationship: PASS
fact_events_repo_key_relationship: PASS
fact_events_event_type_key_relationship: PASS

Done! 45+ tests executed, 45+ passed, 0 failed
```

### Step 5: Verify Data Quality

```sql
-- Check dimension row counts
SELECT 'dim_actor' as table_name, COUNT(*) as row_count 
FROM GITHUB_DBT.MARTS.DIM_ACTOR
UNION ALL
SELECT 'dim_repository', COUNT(*) FROM GITHUB_DBT.MARTS.DIM_REPOSITORY
UNION ALL
SELECT 'dim_event_type', COUNT(*) FROM GITHUB_DBT.MARTS.DIM_EVENT_TYPE
UNION ALL
SELECT 'fact_events', COUNT(*) FROM GITHUB_DBT.MARTS.FACT_EVENTS;

-- Expected:
-- dim_actor: ~100K
-- dim_repository: ~150K
-- dim_event_type: 11
-- fact_events: ~2.5M
```

### Step 6: Test Star Schema Join

```sql
-- Query across all tables
SELECT 
  f.event_date,
  et.event_type,
  et.event_category,
  a.actor_login,
  a.is_bot,
  r.repo_name,
  COUNT(*) as event_count
FROM GITHUB_DBT.MARTS.FACT_EVENTS f
LEFT JOIN GITHUB_DBT.MARTS.DIM_ACTOR a ON f.actor_key = a.actor_key
LEFT JOIN GITHUB_DBT.MARTS.DIM_REPOSITORY r ON f.repo_key = r.repo_key
LEFT JOIN GITHUB_DBT.MARTS.DIM_EVENT_TYPE et ON f.event_type_key = et.event_type_key
GROUP BY f.event_date, et.event_type, et.event_category, a.actor_login, a.is_bot, r.repo_name
ORDER BY event_count DESC
LIMIT 10;

-- Expected: Fast query with aggregated results
```

---

## ER Diagram

```sql
-- Generate ERD (Snowflake)
SELECT 
  COLUMN_NAME, DATA_TYPE, IS_NULLABLE, 
  CONSTRAINT_TYPE, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'MARTS'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

---

## Integration with Phase 10

Phase 9 output is the foundation for Phase 10:

**Incremental Updates**:
- Convert fact_events to incremental (only new events)
- Update dimensions with change tracking (SCD Type 2 for actors)
- Add merge logic for efficient updates

**Optimization**:
- Add clustering on frequently filtered columns
- Create materialized views for common queries
- Add indexes for join columns

---

## Common Queries for Phase 13 (Power BI)

### Top Repositories by Activity
```sql
SELECT 
  r.repo_name,
  COUNT(*) as event_count,
  COUNT(DISTINCT f.actor_key) as unique_contributors,
  COUNT(DISTINCT et.event_type) as event_types
FROM GITHUB_DBT.MARTS.FACT_EVENTS f
LEFT JOIN GITHUB_DBT.MARTS.DIM_REPOSITORY r ON f.repo_key = r.repo_key
LEFT JOIN GITHUB_DBT.MARTS.DIM_EVENT_TYPE et ON f.event_type_key = et.event_type_key
GROUP BY r.repo_name
ORDER BY event_count DESC
LIMIT 20;
```

### Developer Activity by Day
```sql
SELECT 
  f.event_date,
  a.actor_login,
  COUNT(*) as events,
  COUNT(DISTINCT f.repo_key) as repos_touched
FROM GITHUB_DBT.MARTS.FACT_EVENTS f
LEFT JOIN GITHUB_DBT.MARTS.DIM_ACTOR a ON f.actor_key = a.actor_key
GROUP BY f.event_date, a.actor_login
ORDER BY f.event_date DESC, events DESC;
```

### Event Type Distribution
```sql
SELECT 
  et.event_category,
  et.event_type,
  COUNT(*) as event_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percent
FROM GITHUB_DBT.MARTS.FACT_EVENTS f
LEFT JOIN GITHUB_DBT.MARTS.DIM_EVENT_TYPE et ON f.event_type_key = et.event_type_key
GROUP BY et.event_category, et.event_type
ORDER BY event_count DESC;
```

---

## Troubleshooting

### Issue: "Foreign key constraint violation"
```
Error: Referenced key not found in dim_actor
```
**Solution**: Ensure dimension is fully populated before fact table

### Issue: "Slow queries on fact table"
```
Warning: Query on fact_events takes >30 seconds
```
**Solution**: 
- Add clustering: `ALTER TABLE FACT_EVENTS CLUSTER BY (event_date, repo_key)`
- Add indexes on foreign keys
- Use smaller time ranges in filters

### Issue: "Surrogate key conflicts"
```
Error: Duplicate surrogate key generated
```
**Solution**: Verify natural key uniqueness in source data

---

## Files Created

| File | Purpose |
|------|---------|
| models/marts/dimensions/dim_actor.sql | Actor dimension (SCD Type 2) |
| models/marts/dimensions/dim_repository.sql | Repository dimension |
| models/marts/dimensions/dim_event_type.sql | Event type dimension |
| models/marts/facts/fact_events.sql | Transaction fact table |
| models/marts/marts_models.yml | Tests & documentation |

---

## Phase 9 Checklist

- [ ] dbt_utils installed (dbt deps)
- [ ] dim_actor created (~100K rows)
- [ ] dim_repository created (~150K rows)
- [ ] dim_event_type created (11 rows)
- [ ] fact_events created (~2.5M rows)
- [ ] All foreign key relationships validated
- [ ] 45+ tests pass
- [ ] Star schema join query works
- [ ] Documentation generated

---

## Next Steps

1. ✓ Run `dbt run --models marts`
2. ✓ Execute `dbt test --models marts`
3. ✓ Verify dimension row counts
4. ✓ Test star schema query
5. → **Phase 10**: Convert to incremental models for efficiency

---

**Status**: ✅ Complete  
**Phase**: 9 of 15  
**Next Phase**: Phase 10 - Incremental dbt Models  
**Estimated Time**: 2-3 hours to complete Phase 10