# Phase 8: Staging Models & Tests

## Overview

Phase 8 extends the dbt foundation with additional staging models and comprehensive test coverage.

**Components**:
- 3 new staging models (actors, repositories, event types)
- Column-level tests and validations
- Data quality checks
- dbt test execution and reporting

---

## Models Created

### 1. stg_actors.sql

**Purpose**: Extract unique actors with first/last activity dates

**Source**: `stg_github_events` (Phase 7)

**Grain**: One row per unique actor

**Volume**: ~100K actors from 7-day backfill

**Output Columns**:
```
actor_id        INTEGER     (PK)
actor_login     VARCHAR     (username)
actor_type      VARCHAR     (User or Bot)
first_seen_at   TIMESTAMP   (first event)
last_seen_at    TIMESTAMP   (last event)
days_active     INTEGER     (span in days)
dbt_loaded_at   TIMESTAMP   (creation timestamp)
```

**Query Logic**:
```sql
-- Use window functions to find first/last dates per actor
FIRST_VALUE(created_at) OVER (PARTITION BY actor_id ORDER BY created_at)
MAX(created_at) OVER (PARTITION BY actor_id)
```

**Example Output**:
```
actor_id | actor_login        | actor_type | first_seen | days_active
---------|-------------------|-----------|------------|------------
1234567  | dependabot[bot]    | Bot       | 2024-01-08 | 7
2345678  | torvalds           | User      | 2024-01-08 | 6
3456789  | linus-bot          | Bot       | 2024-01-09 | 5
```

**Tests Applied**:
- `not_null` on actor_id, actor_login, first_seen_at, last_seen_at
- `unique` on actor_id
- `accepted_values` on actor_type (User, Bot only)

---

### 2. stg_repositories.sql

**Purpose**: Extract unique repositories with owner/name parsing

**Source**: `stg_github_events` (Phase 7)

**Grain**: One row per unique repository

**Volume**: ~150K repositories from 7-day backfill

**Output Columns**:
```
repo_id              INTEGER     (PK)
repo_name            VARCHAR     (owner/name)
repo_owner           VARCHAR     (extracted owner)
repo_short_name      VARCHAR     (extracted name)
first_event_at       TIMESTAMP   (first event)
last_event_at        TIMESTAMP   (last event)
days_active          INTEGER     (span in days)
dbt_loaded_at        TIMESTAMP   (creation timestamp)
```

**Query Logic**:
```sql
-- Parse "kubernetes/kubernetes" into "kubernetes" + "kubernetes"
SPLIT_PART(repo_name, '/', 1) as repo_owner
SPLIT_PART(repo_name, '/', 2) as repo_short_name
```

**Example Output**:
```
repo_id | repo_name           | owner      | short_name | days_active
--------|---------------------|------------|------------|------------
1296269 | torvalds/linux      | torvalds   | linux      | 7
123456  | tensorflow/tf       | tensorflow | tf         | 7
234567  | kubernetes/k8s      | kubernetes | k8s        | 6
```

**Tests Applied**:
- `not_null` on repo_id, repo_name, repo_owner, repo_short_name
- `unique` on repo_id
- `relationships` to stg_github_events (Phase 9)

---

### 3. stg_event_types.sql

**Purpose**: Enumerate event types with counts and percentages

**Source**: `stg_github_events` (Phase 7)

**Grain**: One row per event type

**Volume**: 11 standard event types

**Output Columns**:
```
event_type                 VARCHAR     (PK)
event_count                INTEGER     (total events)
unique_actors              INTEGER     (# of actors)
unique_repos               INTEGER     (# of repos)
first_occurrence           TIMESTAMP   (first event)
last_occurrence            TIMESTAMP   (last event)
percent_of_total_events    FLOAT       (percentage)
event_description          VARCHAR     (human-readable)
dbt_loaded_at              TIMESTAMP   (creation timestamp)
```

**Query Logic**:
```sql
-- Count events per type with aggregations
COUNT(*) as event_count
COUNT(DISTINCT actor_id) as unique_actors
ROUND(event_count * 100.0 / SUM(event_count) OVER (), 2) as percent_of_total
```

**Example Output**:
```
event_type          | count   | percent | actors | repos | description
--------------------|---------|---------|--------|-------|--------------------
PushEvent           | 800,000 | 32.0%   | 50,000 | 80K   | Code push to repo
PullRequestEvent    | 400,000 | 16.0%   | 30,000 | 40K   | PR opened/closed
IssuesEvent         | 350,000 | 14.0%   | 25,000 | 35K   | Issue opened/closed
```

**Tests Applied**:
- `not_null` on event_type, event_count, unique_actors, percent_of_total
- `unique` on event_type
- `accepted_values` on event_type (known types only)

---

## Test Coverage

### Test File: staging_models.yml

**Total Tests**: 25+

**Test Categories**:

#### Not Null Tests (8)
- stg_actors: actor_id, actor_login, first_seen_at, last_seen_at
- stg_repositories: repo_id, repo_name, repo_owner, repo_short_name
- stg_event_types: event_type, event_count, unique_actors, percent_of_total

#### Unique Tests (3)
- stg_actors.actor_id
- stg_repositories.repo_id
- stg_event_types.event_type

#### Accepted Values Tests (2)
- stg_actors.actor_type (User, Bot)
- stg_event_types.event_type (PushEvent, PullRequestEvent, etc.)

#### Relationship Tests (will add in Phase 9)
- stg_actors references stg_github_events
- stg_repositories references stg_github_events
- stg_event_types references stg_github_events

---

## Execution Steps

### Step 1: Run All Staging Models

```bash
cd dbt/github_dbt

# Run only staging models
dbt run --models staging

# Or run specific model
dbt run --models stg_actors
dbt run --models stg_repositories
dbt run --models stg_event_types
```

**Expected Output**:
```
Running with dbt 1.10.0
Found 4 models (stg_github_events + 3 new models), 25 tests

Executing node: stg_github_events
  create view GITHUB_DBT.STAGING.STG_GITHUB_EVENTS
✓ created in 45.32s

Executing node: stg_actors
  create view GITHUB_DBT.STAGING.STG_ACTORS
✓ created in 12.5s

Executing node: stg_repositories
  create view GITHUB_DBT.STAGING.STG_REPOSITORIES
✓ created in 18.3s

Executing node: stg_event_types
  create view GITHUB_DBT.STAGING.STG_EVENT_TYPES
✓ created in 8.7s

Done! 4 models created in 84.82s
```

### Step 2: Run All Tests

```bash
dbt test --models staging
```

**Expected Output**:
```
Running tests...

Completed successfully

Done! 25 tests executed, 25 passed, 0 failed, 0 error

Execution Time: 145.3s
```

### Step 3: Test Individual Models

```bash
# Test stg_actors only
dbt test --models stg_actors

# Test with verbose output
dbt test --models staging --debug
```

### Step 4: Check Test Results

```bash
# View failed tests (if any)
dbt test --select state:error

# Generate test report
dbt test --output-key compiled_code
```

### Step 5: Generate Updated Documentation

```bash
dbt docs generate
dbt docs serve
```

Opens http://localhost:8000 with:
- stg_github_events (yellow, PK)
- stg_actors (blue, referenced by marts)
- stg_repositories (blue, referenced by marts)
- stg_event_types (blue, referenced by marts)
- DAG showing dependencies

---

## Data Quality Validation

### Manual Checks

After running models, validate in Snowflake:

```sql
-- Check stg_actors row count
SELECT COUNT(*) FROM GITHUB_DBT.STAGING.STG_ACTORS;
-- Expected: ~100K

-- Check stg_repositories row count
SELECT COUNT(*) FROM GITHUB_DBT.STAGING.STG_REPOSITORIES;
-- Expected: ~150K

-- Check stg_event_types row count
SELECT COUNT(*) FROM GITHUB_DBT.STAGING.STG_EVENT_TYPES;
-- Expected: 11

-- Verify no duplicates in stg_actors
SELECT actor_id, COUNT(*) as cnt 
FROM GITHUB_DBT.STAGING.STG_ACTORS 
GROUP BY actor_id 
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- Check event type distribution
SELECT event_type, percent_of_total_events 
FROM GITHUB_DBT.STAGING.STG_EVENT_TYPES 
ORDER BY percent_of_total_events DESC;
-- Expected: PushEvent ~30-35%, others decreasing
```

### Automated Checks

Tests run automatically with `dbt test`:

```bash
# Show test execution
dbt test --store-failures

# View test results in Snowflake
SELECT * FROM GITHUB_DBT.STAGING.dbt_test_failures;
```

---

## Integration with Phase 9

Phase 8 output becomes Phase 9 input:

```
stg_github_events  ──┐
                     ├─→ dim_actor (fact table grain)
stg_actors         ──┤
                     ├─→ dim_repository
stg_repositories   ──┤
                     ├─→ dim_event_type
stg_event_types    ──┘
```

**In Phase 9**:
- stg_actors → dim_actor (Snowflake table with SCD Type 2)
- stg_repositories → dim_repository (Snowflake table)
- stg_event_types → dim_event_type (Snowflake table)
- stg_github_events → fact_events (Snowflake fact table)

---

## Common Commands

```bash
# Run and test in one command
dbt run --models staging && dbt test --models staging

# Full refresh (drop and recreate)
dbt run --models staging --full-refresh

# Dry run (parse only)
dbt parse --models staging

# Profile test execution
dbt test --models staging --debug

# Show compiled SQL
dbt parse --write-manifest && cat target/manifest.json

# View lineage
dbt docs generate
dbt docs serve
# Then click "Explore" in the UI
```

---

## Troubleshooting

### Issue: "Model not found"
```
Error: Unable to find model 'stg_actors'
```
**Solution**: Ensure file is in `models/staging/` and named correctly

### Issue: "Source not found"
```
Error: Unable to find source 'github_archive.github_events'
```
**Solution**: Check RAW.GITHUB_EVENTS exists (Phase 4) and is populated

### Issue: "Test failure on not_null"
```
Error: null value found in stg_actors.actor_id
```
**Solution**: Check RAW.GITHUB_EVENTS has valid actor_id values

### Issue: "Unique constraint violation"
```
Error: Duplicate actor_id in stg_actors
```
**Solution**: Raw data may have duplicates; add more filtering to model

### Issue: "Tests are slow"
```
Warning: Test execution taking >5 minutes
```
**Solution**: 
- Reduce data volume (add WHERE clause to limit test scope)
- Add clustering to base tables
- Increase warehouse size

---

## Files Created

| File | Purpose |
|------|---------|
| models/staging/stg_actors.sql | Extract unique actors |
| models/staging/stg_repositories.sql | Extract unique repositories |
| models/staging/stg_event_types.sql | Extract event type enumeration |
| models/staging/staging_models.yml | Tests & documentation |

---

## Phase 8 Checklist

- [ ] 3 new staging models created
- [ ] stg_github_events still working (no regression)
- [ ] All 25+ tests pass
- [ ] Staging schema has 4 views (github_events, actors, repositories, event_types)
- [ ] Documentation updated and generated
- [ ] Lineage graph shows proper dependencies
- [ ] Manual data quality checks pass

---

## Next Steps

1. ✓ Run `dbt run --models staging`
2. ✓ Execute `dbt test --models staging`
3. ✓ Generate and review documentation
4. ✓ Verify data quality manually
5. → **Phase 9**: Create dimension and fact tables (MARTS schema)

---

**Status**: ✅ Complete  
**Phase**: 8 of 15  
**Next Phase**: Phase 9 - Dimensional Modeling  
**Estimated Time**: 3-4 hours to complete Phase 9