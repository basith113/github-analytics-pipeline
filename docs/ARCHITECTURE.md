# System Architecture – GitHub Analytics Pipeline

Comprehensive documentation of the technical architecture, data flow, and design decisions.

---

## 1. System Overview

The GitHub Analytics Pipeline is a modern, scalable data engineering platform that:

- **Extracts** GitHub event data from GH Archive (7+ years of publicly available data)
- **Loads** raw events into Snowflake with deduplication tracking
- **Transforms** data through staging and dimensional models using dbt
- **Tests** data quality at every layer
- **Serves** analytics-ready data to Power BI for visualization
- **Orchestrates** the entire workflow with Apache Airflow

### Key Design Principles

1. **Separation of Concerns**: Clear boundaries between extraction, loading, transformation, and serving
2. **Idempotency**: Operations can be re-run without creating duplicates
3. **Scalability**: Designed to handle petabyte-scale data via Snowflake
4. **Observability**: Comprehensive logging at every stage
5. **Testability**: Data quality tests at each layer
6. **Maintainability**: Self-documenting via dbt and extensive documentation

---

## 2. Architecture Layers

### 2.1 Data Source Layer – GH Archive

**Source**: https://www.gharchive.org/

**Format**: 
- Hourly JSON files: `YYYY-MM-DD-H.json.gz`
- Each file contains ~10,000 GitHub events
- Events span: pushes, pull requests, issues, comments, etc.

**Characteristics**:
- ✅ Free and publicly available
- ✅ Complete GitHub event history (since 2011)
- ✅ Hourly updates (new files every hour at :00 UTC)
- ❌ Historical data (can't retroactively update past events)

**Ingestion Strategy**:
- **Backfill**: Download all hourly files from past 7 days
- **Incremental**: Download latest hourly file every hour
- **Deduplication**: Track loaded files in `RAW.LOAD_HISTORY`

---

### 2.2 Ingestion Layer – Python

**Location**: `ingestion/`

**Components**:

#### 2.2.1 GH Archive Client (`gharchive_client.py`)

Responsibilities:
- Build GH Archive URLs for specific dates/hours
- Download hourly JSON files
- Handle gzip decompression
- Validate file integrity
- Implement retry logic with exponential backoff
- Handle rate limiting (if applicable)

**Interface**:
```python
class GHArchiveClient:
    def download_file(date: datetime, hour: int) -> bytes
    def get_available_files(start_date: datetime, end_date: datetime) -> List[str]
    def validate_file(file_data: bytes) -> bool
```

#### 2.2.2 Snowflake Loader (`snowflake_loader.py`)

Responsibilities:
- Establish and manage Snowflake connections
- Parse JSON events and convert to rows
- Batch insert records efficiently
- Track loaded files in metadata table
- Implement error handling and retry logic
- Provide transaction support

**Interface**:
```python
class SnowflakeLoader:
    def load_json_events(events: List[dict], file_name: str) -> int
    def file_already_loaded(file_name: str) -> bool
    def record_load(file_name: str) -> None
    def get_last_loaded_file() -> str
```

#### 2.2.3 Helpers (`helpers.py`)

Reusable utilities:
- Logging configuration and setup
- Date/time utilities
- Configuration loading from YAML
- Error handling decorators
- Retry logic implementations

---

### 2.3 Raw Data Layer – Snowflake

**Database**: `GITHUB_DBT`  
**Schema**: `RAW`

#### 2.3.1 Core Raw Table: `GITHUB_EVENTS`

Stores complete event data as semi-structured JSON.

**Design Rationale**:
- Use `VARIANT` type to store raw JSON without predefined schema
- Allows flexibility as GH Archive API may evolve
- Parse/extract fields in staging layer using `GET_PATH()` and `GET_JSON_OBJECT()`

**Schema**:
```sql
CREATE TABLE RAW.GITHUB_EVENTS (
    RAW_DATA VARIANT,              -- Full JSON event object
    FILE_NAME STRING,              -- e.g., "2024-01-15-3.json.gz"
    LOAD_TS TIMESTAMP_NTZ,         -- When record was loaded
    
    PRIMARY KEY (RAW_DATA:id, LOAD_TS)  -- Composite key for dedup
);
```

**Sample Data**:
```json
{
    "id": 12345678,
    "type": "PushEvent",
    "actor": {
        "id": 1234,
        "login": "octocat",
        "avatar_url": "https://avatars.githubusercontent.com/u/1234?v=4"
    },
    "repo": {
        "id": 5678,
        "name": "octocat/Hello-World",
        "url": "https://api.github.com/repos/octocat/Hello-World"
    },
    "payload": { ... },
    "public": true,
    "created_at": "2024-01-15T10:30:00Z"
}
```

#### 2.3.2 Metadata Table: `LOAD_HISTORY`

Tracks which files have been loaded to prevent duplicates.

**Schema**:
```sql
CREATE TABLE RAW.LOAD_HISTORY (
    FILE_NAME STRING PRIMARY KEY,  -- e.g., "2024-01-15-3.json.gz"
    LOAD_TS TIMESTAMP_NTZ,         -- When file was loaded
    ROW_COUNT INT,                 -- Number of events in file
    FILE_SIZE_BYTES INT,           -- Size of compressed file
    STATUS STRING,                 -- SUCCESS, FAILED, SKIPPED
    ERROR_MESSAGE STRING           -- If STATUS = FAILED
);
```

**Why This Design**:
- ✅ Idempotent: Can safely re-run without duplicates
- ✅ Auditable: See exactly what was loaded and when
- ✅ Debuggable: Identify failed loads and retry
- ✅ Performant: Quick lookup with FILE_NAME index

---

### 2.4 Staging Layer – dbt

**Database**: `GITHUB_DBT`  
**Schema**: `STAGING`

**Purpose**: Flatten and cleanse raw JSON into tabular format

#### 2.4.1 Staging Model: `stg_github_events`

Transforms raw JSON into clean, documented columns.

**Source**: `RAW.GITHUB_EVENTS`

**Key Transformations**:
- Extract nested JSON fields using `GET_JSON_OBJECT()`
- Parse timestamps into proper `TIMESTAMP_NTZ` format
- Derive new columns:
  - `event_date`: Date from `created_at`
  - `event_hour`: Hour from `created_at`
- Add surrogate keys if needed

**Schema**:
```sql
-- Core fields
event_id STRING,
event_type STRING,
created_at TIMESTAMP_NTZ,
event_date DATE,
event_hour INT,

-- Actor fields
actor_id INT,
actor_login STRING,
actor_type STRING,

-- Repository fields
repo_id INT,
repo_name STRING,
repo_url STRING,

-- Payload details (varies by event type)
push_size INT,
pull_request_id INT,
issue_id INT,
issue_action STRING,

-- Metadata
file_name STRING,
load_ts TIMESTAMP_NTZ,
dbt_created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
```

**dbt Tests**:
- `not_null` on `event_id`, `event_type`, `created_at`
- `unique` on `event_id`
- `accepted_values` on `event_type` (PushEvent, PullRequestEvent, etc.)
- `relationships` to parent entities (repo, actor)

---

### 2.5 Mart Layer – dbt

**Database**: `GITHUB_DBT`  
**Schema**: `MARTS`

Purpose: Create optimized dimensional models for analytics

#### 2.5.1 Dimensions

Slowly changing dimensions describing entities.

##### **dim_actor**
- `actor_id` (PK)
- `actor_login`
- `actor_type` (User, Bot, Organization)
- `first_seen_date`
- `most_recent_event_date`
- `total_events`

##### **dim_repository**
- `repo_id` (PK)
- `repo_name`
- `repo_url`
- `owner_login`
- `first_event_date`
- `is_active` (based on recent activity)
- `language` (if available from GH API)

##### **dim_event_type**
- `event_type_id` (PK)
- `event_type_name` (PushEvent, PullRequestEvent, etc.)
- `event_category` (Code, PR, Issue, etc.)
- `is_success_event` (certain types are positive signals)

#### 2.5.2 Facts

Grain-specific fact tables for efficient analysis.

##### **fact_events**
- **Grain**: One row per event
- **Dimensions**: actor, repository, event_type
- **Measures**:
  - `event_count` (always 1, used for aggregation)
  - `is_public_event` (boolean)
- **Timestamp**: `created_at`

##### **fact_push_events** (Incremental)
- **Grain**: One row per push event
- **Filters**: Only PushEvent type
- **Additional Measures**:
  - `commits_count`
  - `branches_pushed`
  - `distinct_sizes`

---

### 2.6 Serving Layer – Power BI

**Purpose**: Interactive dashboards and reports

**Connection**: Direct Snowflake ODBC connection to `MARTS` schema

**Dashboards**:

1. **Activity Overview**
   - Total events (KPI)
   - Events by day (line chart)
   - Events by hour (heatmap)

2. **Community Analysis**
   - Top developers (bar chart)
   - Top repositories (bar chart)
   - New developers this week (metric)

3. **Event Breakdown**
   - Event type distribution (pie chart)
   - Push vs. Pull request trends (line chart)
   - Issue activity (scatter)

4. **Data Quality**
   - Load success rate
   - Data freshness (time since last load)
   - Row count growth over time

---

### 2.7 Orchestration Layer – Apache Airflow

**Purpose**: Schedule and monitor the entire pipeline

**DAG**: `github_pipeline_dag`

**Workflow**:
```
download_latest_hour
    ↓
load_to_snowflake
    ↓
dbt_run_staging
    ↓
dbt_test
    ↓
dbt_run_marts
    ↓
refresh_power_bi (optional)
    ↓
cleanup_and_notify
```

**Schedule**: Hourly (at :05 past each hour)

**Features**:
- Retry on failure (3 attempts)
- Email alerts on critical failures
- Task dependency management
- Monitoring and logging

---

## 3. Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      1. DATA SOURCE                               │
│                      GH Archive                                   │
│              https://data.gharchive.org/                          │
│                                                                   │
│  • YYYY-MM-DD-H.json.gz (hourly files)                           │
│  • ~10K events per hour                                          │
│  • 2.5+ billion events in archive                                │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       │ Backfill (Phase 4):
                       │   1. Loop dates: yesterday - 7 days ago
                       │   2. Loop hours: 0-23
                       │   3. Download each YYYY-MM-DD-H.json.gz
                       │
                       │ Incremental (Phase 5):
                       │   1. Determine latest available file
                       │   2. Check if already loaded
                       │   3. Download if new
                       │
                       ▼
        ┌──────────────────────────────┐
        │  2. INGESTION (Python)        │
        │  ┌────────────────────────┐  │
        │  │ gharchive_client.py    │  │
        │  │ • Download file        │  │
        │  │ • Decompress .gz       │  │
        │  │ • Validate JSON        │  │
        │  │ • Handle retries       │  │
        │  └────────────────────────┘  │
        │  ┌────────────────────────┐  │
        │  │ snowflake_loader.py    │  │
        │  │ • Parse JSON events    │  │
        │  │ • Check for duplicates │  │
        │  │ • Batch insert        │  │
        │  │ • Log to LOAD_HISTORY │  │
        │  └────────────────────────┘  │
        └──────────────────────┬────────┘
                               │
                               ▼
        ┌──────────────────────────────────────┐
        │ 3. SNOWFLAKE RAW LAYER                │
        │    GITHUB_DBT.RAW                     │
        │ ┌──────────────┐  ┌──────────────┐  │
        │ │ GITHUB_EVENTS│  │ LOAD_HISTORY │  │
        │ │ • RAW_DATA   │  │ • FILE_NAME  │  │
        │ │ • FILE_NAME  │  │ • LOAD_TS    │  │
        │ │ • LOAD_TS    │  │ • ROW_COUNT  │  │
        │ └──────────────┘  └──────────────┘  │
        └──────────────────┬───────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │ 4. dbt TRANSFORMATIONS               │
        │    (nightly or hourly)               │
        │                                      │
        │ Phase 1: STAGING                     │
        │ • stg_github_events                 │
        │   (flatten JSON, extract fields)    │
        │                                      │
        │ Phase 2: MART                        │
        │ • dim_actor                         │
        │ • dim_repository                    │
        │ • dim_event_type                    │
        │ • fact_events                       │
        │ • fact_push_events                  │
        └──────────────────┬───────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │ 5. SNOWFLAKE MARTS LAYER              │
        │    GITHUB_DBT.MARTS                  │
        │    (optimized for analytics)         │
        │                                      │
        │  DIMENSIONS          FACTS           │
        │  • dim_actor         • fact_events   │
        │  • dim_repository    • fact_push...  │
        │  • dim_event_type                    │
        └──────────────────┬───────────────────┘
                           │
                           │ ODBC Connection
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │ 6. POWER BI DASHBOARDS                │
        │    (Interactive Analytics)           │
        │                                      │
        │  • Activity Overview                 │
        │  • Community Analysis                │
        │  • Event Breakdown                   │
        │  • Data Quality Monitor              │
        └──────────────────────────────────────┘
```

---

## 4. Scalability Considerations

### 4.1 Volume Growth

**Current Load**:
- ~10K events/hour
- ~240K events/day
- ~7.2M events/month

**Scalability Approach**:
- ✅ Snowflake handles unlimited row growth
- ✅ Incremental models process only new data
- ✅ Partitioning by `LOAD_TS` for faster queries
- ✅ Clustering by `event_date` for common filters

### 4.2 Performance Optimization

1. **Indexing**: Snowflake automatically optimizes clustering
2. **Partitioning**: Natural partition by date
3. **Caching**: Query result caching via Snowflake
4. **Materialized Views**: Convert slow aggregations to views
5. **Warehouse Sizing**: Scale compute as needed (manual or auto-scaling)

### 4.3 Cost Optimization

- ✅ Incremental loads = minimal compute
- ✅ dbt incremental models = faster runs
- ✅ Snowflake auto-suspend on warehouse
- ✅ Query optimization via ANALYZE TABLE

---

## 5. Security & Compliance

### 5.1 Data Protection

- ✅ Credentials in `.env` (never committed)
- ✅ Snowflake encryption at rest
- ✅ HTTPS for all external API calls
- ✅ No PII extraction from public events

### 5.2 Access Control

- Role-based access (RAW, STAGING, MARTS views)
- Snowflake RBAC (accountadmin, transformer, analyst roles)

### 5.3 Audit Trail

- LOAD_HISTORY tracks all ingestion
- dbt artifacts track transformation lineage
- Logs for all operations

---

## 6. Error Handling & Recovery

### 6.1 Failure Points

| Component | Failure | Recovery |
|-----------|---------|----------|
| Download | Network error | Retry with exponential backoff |
| Decompress | Corrupted file | Log error, skip file, continue |
| Parse | Invalid JSON | Graceful parsing, null handling |
| Load | Constraint violation | Log, skip row, continue |
| dbt | Model error | Fail loudly, alert, require manual fix |

### 6.2 Idempotency Guarantees

- ✅ Duplicate file loads prevented by LOAD_HISTORY check
- ✅ dbt models are idempotent (re-run same result)
- ✅ Snowflake transactions ensure all-or-nothing loads

---

## 7. Future Enhancements

### Phase Enhancement Roadmap

- [ ] **Real-time Streaming**: Kafka for sub-minute latency
- [ ] **ML Features**: Anomaly detection, trend forecasting
- [ ] **Advanced Analytics**: Network analysis, community detection
- [ ] **Multi-Cloud**: Replicate to other data warehouses
- [ ] **Self-Healing**: Automated failure recovery
- [ ] **Cost Analytics**: Show cost per query, model
- [ ] **Data Catalog**: Metadata management system

---

**Status**: ✅ Complete  
**Last Updated**: June 2026  
**Architecture Version**: 1.0