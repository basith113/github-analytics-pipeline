# Phase 3: GH Archive Ingestion Utilities – Complete Guide

## Overview

Phase 3 creates reusable Python utilities for ingesting GitHub events from GH Archive into Snowflake. These utilities are the foundation for both backfill (Phase 4) and incremental loading (Phase 5).

---

## Architecture

```
Python Ingestion Layer
├── helpers.py (Utilities & logging)
│   ├── Configuration loading (YAML)
│   ├── Date/time utilities
│   ├── Logging setup
│   ├── Retry decorators
│   └── Common functions
│
├── gharchive_client.py (Download from GH Archive)
│   ├── Build URLs
│   ├── Download files
│   ├── Decompress .gz
│   ├── Parse NDJSON
│   └── Validate events
│
└── snowflake_loader.py (Load into Snowflake)
    ├── Connection management
    ├── Insert events
    ├── Batch processing
    ├── Track loads
    └── Error handling
```

---

## Files Created

### 1. `ingestion/utils/helpers.py`

Core utility library providing:
- Configuration management
- Logging setup
- Date/time utilities  
- Retry logic
- Error handling
- File utilities
- JSON utilities

**Key Functions**:

```python
# Configuration
load_config(config_path) → Dict
load_logging_config(config_path) → None

# Logging
get_logger(name) → Logger

# Date/Time
get_utc_now() → datetime
get_last_n_days(days) → List[datetime]
get_date_hour_string(date, hour) → str
parse_date_hour_string(date_hour_str) → (datetime, int)
get_latest_available_file_name() → str

# Retry Logic
@retry(max_attempts=3, delay_seconds=5, backoff=2.0)

# Utilities
retry(max_attempts, delay_seconds, backoff) → Decorator
Timer(name, logger) → Context manager
```

### 2. `ingestion/utils/gharchive_client.py`

Downloads GitHub event data from GH Archive with:
- Automatic retries
- File validation
- JSON parsing
- Error handling

**Class: GHArchiveClient**

```python
# Constructor
client = GHArchiveClient(base_url=..., timeout=...)

# Methods
client.build_file_url(date, hour) → str
client.download_events(date, hour, validate=True) → List[dict]
client.file_exists(date, hour) → bool
client.get_available_files(start_date, end_date) → List[str]
client.close()
```

**Example Usage**:

```python
from datetime import datetime
from ingestion.utils.gharchive_client import GHArchiveClient

# Create client
client = GHArchiveClient()

# Download events for specific hour
date = datetime(2024, 1, 15)
events = client.download_events(date, hour=3)

print(f"Downloaded {len(events)} events")
# Downloaded 12345 events

# Check if file exists
exists = client.file_exists(date, hour=3)

# Get available files in date range
from datetime import timedelta
end_date = date
start_date = date - timedelta(days=7)
files = client.get_available_files(start_date, end_date)

# Use context manager
with GHArchiveClient() as client:
    events = client.download_events(date, hour=3)
```

### 3. `ingestion/utils/snowflake_loader.py`

Manages Snowflake connections and data loading:
- Connection pooling
- Batch inserts
- Duplicate prevention
- Metadata tracking
- Transaction management

**Class: SnowflakeConnection**

```python
# Constructor (reads from environment)
conn = SnowflakeConnection(
    user=...,
    password=...,
    account=...,
    warehouse=...,
    database=...,
    schema=...,
    role=...
)

# Methods
cursor = conn.cursor()
results = conn.execute(sql, params)
conn.commit()
conn.rollback()
conn.close()
```

**Class: SnowflakeLoader**

```python
# Constructor
loader = SnowflakeLoader(connection=..., batch_size=5000)

# Methods
loader.load_events(events, file_name, skip_if_exists=True) → int
loader.file_already_loaded(file_name) → bool
loader.get_last_successful_load() → (file_name, timestamp)
loader.record_load_success(file_name, file_hour, row_count, duration_seconds, file_size_bytes)
loader.record_load_failure(file_name, file_hour, error_message)
loader.close()
```

**Example Usage**:

```python
from ingestion.utils.snowflake_loader import SnowflakeLoader, SnowflakeConnection
from ingestion.utils.gharchive_client import GHArchiveClient
from datetime import datetime

# Create loader
loader = SnowflakeLoader()

# Get client
client = GHArchiveClient()

# Download events
date = datetime(2024, 1, 15)
events = client.download_events(date, hour=3)

# Check if already loaded
file_name = "2024-01-15-3.json.gz"
if not loader.file_already_loaded(file_name):
    # Load events
    row_count = loader.load_events(events, file_name)
    
    # Record success
    file_hour = datetime(2024, 1, 15, 3, 0, 0)
    loader.record_load_success(
        file_name,
        file_hour,
        row_count=row_count,
        duration_seconds=45.5
    )
    
    print(f"Loaded {row_count} events")

loader.close()
```

---

## Environment Variables

The utilities read Snowflake credentials from environment variables or `.env` file:

```env
# Snowflake Connection (required)
SNOWFLAKE_USER=your_username
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_ACCOUNT=xy12345.us-east-1
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_DATABASE=GITHUB_DBT
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=ACCOUNTADMIN
```

Load from `.env`:
```python
from dotenv import load_dotenv
load_dotenv()
```

Or pass directly:
```python
conn = SnowflakeConnection(
    user="username",
    password="password",
    account="xy12345.us-east-1"
)
```

---

## Logging

Configure logging via `configs/logging.yaml`:

```python
from ingestion.utils.helpers import get_logger

logger = get_logger(__name__)

logger.debug("Debug message")
logger.info("Info message")
logger.warning("Warning message")
logger.error("Error message", exc_info=True)
```

Logs are written to:
- `logs/pipeline.log` - Main pipeline log
- `logs/ingestion.log` - Ingestion-specific logs
- `logs/snowflake.log` - Snowflake queries
- Console (stdout)

---

## Testing Phase 3 Setup

Run the test script to validate all utilities:

```bash
# From project root
python test_ingestion_setup.py
```

This will test:
1. ✓ Configuration loading
2. ✓ Helper utilities
3. ✓ GH Archive connection
4. ✓ Snowflake connection
5. ✓ Snowflake loader

**Expected Output**:
```
╔══════════════════════════════════════════════════════════╗
║  GitHub Analytics Pipeline - Ingestion Setup Tests      ║
╚══════════════════════════════════════════════════════════╝

====== TEST SUMMARY ======
✓ PASS: Configuration
✓ PASS: Helpers
✓ PASS: GH Archive Connection
✓ PASS: Snowflake Connection
✓ PASS: Snowflake Loader

Total: 5/5 tests passed

🎉 All tests passed! Ready for Phase 4 - Backfill
```

---

## GH Archive File Format

GH Archive files follow a specific naming and format:

**Filename**: `YYYY-MM-DD-H.json.gz`
- `YYYY-MM-DD`: Date in UTC
- `H`: Hour (0-23)
- `.json.gz`: Gzipped JSON

**Example**: `2024-01-15-3.json.gz` = January 15, 2024 at 3:00 UTC

**File Contents**: Newline-delimited JSON (NDJSON)
```json
{"id": 1, "type": "PushEvent", "actor": {...}, "repo": {...}, ...}
{"id": 2, "type": "PullRequestEvent", "actor": {...}, "repo": {...}, ...}
{"id": 3, "type": "IssuesEvent", "actor": {...}, "repo": {...}, ...}
```

**Event Structure**:
```json
{
  "id": 12345678901,
  "type": "PushEvent",
  "actor": {
    "id": 1234567,
    "login": "octocat",
    "avatar_url": "https://avatars.githubusercontent.com/u/1234?v=4"
  },
  "repo": {
    "id": 1296269,
    "name": "octocat/Hello-World",
    "url": "https://api.github.com/repos/octocat/Hello-World"
  },
  "payload": {
    "ref": "refs/heads/main",
    "before": "9049aeb3bac0504f7f34c4b16b2386e55b79b524",
    "commits": [...]
  },
  "public": true,
  "created_at": "2024-01-15T03:30:00Z"
}
```

---

## Data Flow

```
GH Archive File (on S3/HTTPS)
    ↓
GHArchiveClient.download_events()
    ├─ Build URL (build_file_url)
    ├─ Download file (_download_file)
    ├─ Decompress (_decompress_file)
    ├─ Parse NDJSON (_parse_json_lines)
    └─ Validate (optional, _validate_events)
    ↓
List[dict] of events
    ↓
SnowflakeLoader.load_events()
    ├─ Check if already loaded (file_already_loaded)
    ├─ Batch insert (_insert_events_batch)
    └─ Record in LOAD_HISTORY
    ↓
RAW.GITHUB_EVENTS table
RAW.LOAD_HISTORY table
```

---

## Error Handling

### Automatic Retries

The `@retry` decorator handles transient failures:

```python
@retry(max_attempts=3, delay_seconds=5, backoff=2.0)
def _download_file(self, url: str) -> bytes:
    response = self.session.get(url, timeout=self.timeout)
    response.raise_for_status()
    return response.content
```

- **Attempt 1**: Immediate
- **Attempt 2**: Wait 5 seconds
- **Attempt 3**: Wait 10 seconds (5 * 2.0)

### Exception Handling

```python
try:
    events = client.download_events(date, hour)
    loader.load_events(events, file_name)
except requests.RequestException as e:
    logger.error(f"Download failed: {e}")
except snowflake.connector.errors.ProgrammingError as e:
    logger.error(f"Database error: {e}")
```

### Batch Processing

Failed individual events are logged but don't stop the batch:

```python
for event in events:
    try:
        cursor.execute(insert_sql, event_data)
        inserted += 1
    except Exception as e:
        logger.warning(f"Failed to insert event {event['id']}: {e}")
        # Continue with next event
```

---

## Performance Considerations

### Batch Size

Default batch size is 5000 rows. Adjust based on memory:

```python
loader = SnowflakeLoader(batch_size=10000)  # Larger batches
loader = SnowflakeLoader(batch_size=1000)   # Smaller batches
```

### Connection Pooling

Use context managers for automatic cleanup:

```python
# Recommended
with SnowflakeLoader() as loader:
    loader.load_events(events, file_name)
# Connection automatically closed

# Or manual
loader = SnowflakeLoader()
loader.load_events(events, file_name)
loader.close()
```

### Retry Strategy

Exponential backoff prevents overwhelming services:

```python
# Default (good for most cases)
@retry(max_attempts=3, delay_seconds=5, backoff=2.0)

# Aggressive (for reliable networks)
@retry(max_attempts=2, delay_seconds=2, backoff=1.5)

# Conservative (for flaky networks)
@retry(max_attempts=5, delay_seconds=10, backoff=2.0)
```

---

## Common Scenarios

### Scenario 1: Load Single File

```python
from datetime import datetime
from ingestion.utils.gharchive_client import GHArchiveClient
from ingestion.utils.snowflake_loader import SnowflakeLoader

client = GHArchiveClient()
loader = SnowflakeLoader()

# Download
date = datetime(2024, 1, 15)
events = client.download_events(date, hour=3)

# Load
file_name = "2024-01-15-3.json.gz"
row_count = loader.load_events(events, file_name)

# Record
from ingestion.utils.helpers import get_file_hour_timestamp
file_hour = get_file_hour_timestamp(file_name)
loader.record_load_success(file_name, file_hour, row_count, 45.5)

print(f"Loaded {row_count} events")
```

### Scenario 2: Load Last 7 Days

```python
from datetime import datetime, timedelta
from ingestion.utils.helpers import get_last_n_days

dates = get_last_n_days(7)

for date in dates:
    for hour in range(24):
        events = client.download_events(date, hour)
        file_name = f"{date.strftime('%Y-%m-%d')}-{hour}.json.gz"
        loader.load_events(events, file_name)
```

### Scenario 3: Check Data Quality

```python
# Check most recent load
file_name, timestamp = loader.get_last_successful_load()
print(f"Last load: {file_name} at {timestamp}")

# Check load history
cursor = loader.connection.cursor()
cursor.execute(
    "SELECT FILE_NAME, ROW_COUNT, STATUS FROM RAW.LOAD_HISTORY ORDER BY LOAD_TS DESC LIMIT 10"
)
for row in cursor.fetchall():
    print(row)
```

---

## Troubleshooting

### Issue: "ModuleNotFoundError: No module named 'ingestion'"

**Solution**: Run from project root and ensure `__init__.py` exists
```bash
cd c:\Users\abdul\Basith-Saas\DE\github-analytics-pipeline
python test_ingestion_setup.py
```

### Issue: "Failed to authenticate to Snowflake"

**Solution**: Check `.env` file has correct credentials
```bash
echo %SNOWFLAKE_USER%
echo %SNOWFLAKE_ACCOUNT%
```

### Issue: "File not found" for GH Archive

**Solution**: File may not exist yet. Check availability:
```python
client = GHArchiveClient()
exists = client.file_exists(date, hour)
if not exists:
    print("File not available yet")
```

### Issue: "Connection timeout"

**Solution**: Increase timeout or check network
```python
client = GHArchiveClient(timeout=60)  # 60 seconds
```

---

## Next Steps

Once Phase 3 is validated:

1. Run `test_ingestion_setup.py` and verify all tests pass
2. Proceed to **Phase 4: Initial 7-Day Backfill**
3. Use these utilities in `load_last_7_days.py`

---

## Files Summary

```
ingestion/utils/
├── __init__.py
├── helpers.py           ← Utilities & logging
├── gharchive_client.py  ← GH Archive downloader
└── snowflake_loader.py  ← Snowflake loader

test_ingestion_setup.py  ← Validation script
```

---

**Status**: ✅ Complete  
**Phase**: 3 of 15  
**Next Phase**: Phase 4 - Initial 7-Day Backfill