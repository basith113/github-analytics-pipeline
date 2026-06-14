# Setup Guide – GitHub Analytics Pipeline

Complete step-by-step guide to configure and run the GitHub Analytics Pipeline.

---

## Prerequisites

- **Windows 10/11** (or WSL2)
- **Python 3.11+**
- **Snowflake Account** with administrative access
- **Git** (for version control)
- **Administrator access** to computer (for Task Scheduler)

---

## Step 1: Environment Setup

### 1.1 Create Python Virtual Environment

```bash
cd c:\Users\abdul\Basith-Saas\DE\github-analytics-pipeline
python -m venv venv
venv\Scripts\activate
```

### 1.2 Verify Python Version

```bash
python --version
# Expected output: Python 3.11.x or higher
```

### 1.3 Upgrade pip

```bash
python -m pip install --upgrade pip
```

---

## Step 2: Install Dependencies

### 2.1 Install from requirements.txt

```bash
pip install -r requirements.txt
```

This installs:
- **Data ingestion**: requests, pandas
- **Snowflake**: snowflake-connector-python
- **Transformations**: dbt-core, dbt-snowflake
- **Orchestration**: apache-airflow (for later phases)
- **Development**: pytest, black, mypy

### 2.2 Verify Installation

```bash
# Test imports
python -c "import snowflake; import dbt; import airflow; print('All imports successful!')"
```

---

## Step 3: Snowflake Configuration

### 3.1 Get Snowflake Connection Details

Log in to Snowflake and retrieve:
- **Account**: `xy12345` (found in Account URL: `xy12345.us-east-1.snowflakecomputing.com`)
- **User**: Your Snowflake username
- **Password**: Your Snowflake password
- **Warehouse**: `COMPUTE_WH` (or create new)
- **Database**: Will be created in Phase 2

### 3.2 Create .env File

Create `.env` in project root:

```bash
cp .env .env.local  # or manually create
```

Edit `.env` with your credentials:

```env
# Snowflake Connection
SNOWFLAKE_USER=your_username
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_ACCOUNT=xy12345.us-east-1
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_DATABASE=GITHUB_DBT
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=ACCOUNTADMIN

# Optional: For advanced scenarios
SNOWFLAKE_REGION=us-east-1
SNOWFLAKE_AUTHENTICATOR=externalbrowser
```

### 3.3 Test Snowflake Connection

```python
python -c """
import os
from dotenv import load_dotenv
from snowflake.connector import connect

load_dotenv()

conn = connect(
    user=os.getenv('SNOWFLAKE_USER'),
    password=os.getenv('SNOWFLAKE_PASSWORD'),
    account=os.getenv('SNOWFLAKE_ACCOUNT'),
    warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
)

cursor = conn.cursor()
cursor.execute('SELECT CURRENT_USER()')
print('Connected as:', cursor.fetchone()[0])
conn.close()
"""
```

Expected output:
```
Connected as: your_username
```

---

## Step 4: Configure dbt

### 4.1 Create dbt Profile

Create `~/.dbt/profiles.yml` (Windows: `C:\Users\<username>\.dbt\profiles.yml`):

```yaml
github_dbt:
  outputs:
    dev:
      type: snowflake
      account: xy12345.us-east-1
      user: your_username
      password: your_password
      role: ACCOUNTADMIN
      database: GITHUB_DBT
      schema: STAGING
      warehouse: COMPUTE_WH
      threads: 4
      client_session_keep_alive: false
  target: dev
```

### 4.2 Verify dbt Installation

```bash
cd dbt/github_dbt
dbt debug
```

Expected output:
```
dbt version: 1.10.4
...
All checks passed!
```

---

## Step 5: Verify Project Structure

Run this script to check all required directories exist:

```python
import os
from pathlib import Path

required_dirs = [
    'configs',
    'ingestion/backfill',
    'ingestion/incremental',
    'ingestion/utils',
    'ingestion/metadata',
    'sql/ddl',
    'sql/analysis',
    'sql/validation',
    'dbt/github_dbt/models/staging',
    'dbt/github_dbt/models/marts/dimensions',
    'dbt/github_dbt/models/marts/facts',
    'dbt/github_dbt/tests',
    'dbt/github_dbt/macros',
    'dashboards/powerbi',
    'notebooks',
    'scheduler',
    'docs',
    'logs',
]

missing = [d for d in required_dirs if not os.path.exists(d)]

if missing:
    print("❌ Missing directories:")
    for d in missing:
        print(f"  - {d}")
else:
    print("✅ All required directories exist!")
```

---

## Step 6: Configure Logging

### 6.1 Create logging.yaml

File: `configs/logging.yaml`

```yaml
version: 1
disable_existing_loggers: false

formatters:
  standard:
    format: '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    datefmt: '%Y-%m-%d %H:%M:%S'
  
  detailed:
    format: '%(asctime)s - %(name)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
    datefmt: '%Y-%m-%d %H:%M:%S'

handlers:
  console:
    class: logging.StreamHandler
    level: INFO
    formatter: standard
    stream: ext://sys.stdout
  
  file:
    class: logging.FileHandler
    level: DEBUG
    formatter: detailed
    filename: logs/pipeline.log

loggers:
  ingestion:
    level: DEBUG
    handlers: [console, file]
    propagate: no
  
  snowflake:
    level: INFO
    handlers: [file]
    propagate: no

root:
  level: INFO
  handlers: [console, file]
```

---

## Step 7: Configure Pipeline

### 7.1 Create config.yaml

File: `configs/config.yaml`

```yaml
# GitHub Analytics Pipeline Configuration

# GH Archive Settings
gharchive:
  base_url: "https://data.gharchive.org"
  timeout_seconds: 30
  max_retries: 3
  retry_delay_seconds: 5

# Snowflake Settings
snowflake:
  chunk_size: 5000  # Records per batch insert
  timeout_seconds: 300
  error_handling: "log_and_skip"  # or "fail_on_error"

# Pipeline Phases
pipeline:
  backfill:
    days_to_load: 7
    start_hour: 0
    end_hour: 23
  
  incremental:
    look_back_hours: 1  # Load files from past N hours

# Logging
logging:
  level: "INFO"  # DEBUG, INFO, WARNING, ERROR
  log_file: "logs/pipeline.log"
  max_file_size_mb: 100
  backup_count: 5

# Feature Flags
features:
  validate_on_download: true
  track_load_history: true
  send_alerts_on_failure: false
```

---

## Step 8: Create Log Directory

```bash
mkdir -p logs
```

---

## Verification Checklist

Run through this checklist to verify setup:

```bash
# ✅ Step 1: Python and Virtual Environment
python --version  # Should be 3.11+

# ✅ Step 2: Required packages
pip list | grep -E "snowflake|dbt|airflow|pandas"

# ✅ Step 3: Environment variables loaded
python -c "from dotenv import load_dotenv; load_dotenv(); import os; print('SNOWFLAKE_USER:', os.getenv('SNOWFLAKE_USER'))"

# ✅ Step 4: Snowflake connectivity
python ingestion/utils/test_connection.py

# ✅ Step 5: dbt configuration
cd dbt/github_dbt && dbt debug

# ✅ Step 6: Folder structure
python scripts/verify_structure.py
```

---

## Troubleshooting

### Issue: "ModuleNotFoundError: No module named 'snowflake'"

**Solution**: Reinstall requirements
```bash
pip uninstall snowflake-connector-python -y
pip install snowflake-connector-python==3.17.3
```

### Issue: "dbt debug" fails with "Profile not found"

**Solution**: Create `~/.dbt/profiles.yml` with correct path
```bash
# On Windows, this is:
C:\Users\<username>\.dbt\profiles.yml
```

### Issue: Snowflake connection timeout

**Solution**: Check firewall and Snowflake account settings
```bash
# Test connectivity
ping data.gharchive.org
```

### Issue: "WAREHOUSE not found" in Snowflake

**Solution**: Create warehouse or use existing one
```sql
-- In Snowflake UI, run:
CREATE OR REPLACE WAREHOUSE COMPUTE_WH 
  WITH WAREHOUSE_SIZE = 'XSMALL' 
  AUTO_SUSPEND = 5 
  AUTO_RESUME = TRUE;
```

---

## Next Steps

Once setup is complete:

1. **Phase 2**: Execute [sql/ddl/create_database.sql](../sql/ddl/create_database.sql)
2. **Phase 3**: Run test of ingestion utilities
3. **Phase 4**: Execute 7-day backfill
4. **Phase 5+**: Follow remaining phases sequentially

---

**Status**: ✅ Complete  
**Last Updated**: June 2026