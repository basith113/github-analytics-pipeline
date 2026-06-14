# GitHub Analytics Pipeline

A production-grade, end-to-end data engineering solution that ingests GitHub events from GH Archive, transforms them using dbt, and serves analytics-ready data to Power BI. Built with a focus on scalability, reliability, and maintainability.

## 📋 Project Overview

This project demonstrates enterprise data engineering best practices by building a complete analytics pipeline that:

- **Ingests** GitHub events from GH Archive (7-day backfill + hourly incremental loads)
- **Stores** raw data in Snowflake with deduplication tracking
- **Transforms** data through staging and mart layers using dbt
- **Models** dimensional and fact tables for analytics
- **Tests** data quality at every layer
- **Visualizes** insights via Power BI dashboards
- **Orchestrates** the entire workflow with Apache Airflow

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      GH ARCHIVE (Data Source)                   │
│              https://www.gharchive.org/                          │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             PYTHON INGESTION LAYER                               │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │ Backfill Script  │  │ Incremental      │                     │
│  │ (7-day load)     │  │ Script (hourly)  │                     │
│  └──────────────────┘  └──────────────────┘                     │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             SNOWFLAKE RAW LAYER                                  │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │ GITHUB_EVENTS    │  │ LOAD_HISTORY     │                     │
│  │ (Variant data)   │  │ (Dedup tracking) │                     │
│  └──────────────────┘  └──────────────────┘                     │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             DBT TRANSFORMATION LAYERS                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ STAGING: stg_github_events (flattened JSON)                │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ DIMENSIONS:        FACTS:                                  │ │
│  │ • dim_actor       • fact_events                            │ │
│  │ • dim_repository  • fact_push_events                       │ │
│  │ • dim_event_type                                           │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│             POWER BI DASHBOARDS                                  │
│  • Event Trends (Daily Activity)                                │
│  • Repository Rankings                                          │
│  • Developer Activity                                           │
│  • Event Type Distribution                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
github-analytics-pipeline/
├── README.md                           # This file
├── requirements.txt                    # Python dependencies
├── .env                                # Environment variables (template)
├── .gitignore                          # Git ignore rules
│
├── configs/                            # Configuration files
│   ├── config.yaml                     # Pipeline configuration
│   └── logging.yaml                    # Logging configuration
│
├── ingestion/                          # Data ingestion layer
│   ├── backfill/                       # Backfill scripts
│   │   └── load_last_7_days.py        # Load previous 7 days
│   ├── incremental/                    # Incremental load scripts
│   │   └── load_latest_hour.py        # Load latest hourly file
│   ├── metadata/                       # Metadata queries
│   │   └── load_history.sql           # Track loaded files
│   └── utils/                          # Reusable utilities
│       ├── gharchive_client.py        # GH Archive API client
│       ├── snowflake_loader.py        # Snowflake connection & loading
│       └── helpers.py                 # Utility functions
│
├── sql/                                # SQL scripts
│   ├── ddl/                            # Data definition language
│   │   ├── create_database.sql        # Create GITHUB_DBT database
│   │   ├── create_raw_tables.sql      # Create raw tables
│   │   └── create_load_history.sql    # Create metadata tables
│   ├── analysis/                       # Analysis queries
│   │   ├── event_type_distribution.sql
│   │   ├── top_repositories.sql
│   │   ├── top_developers.sql
│   │   └── daily_activity.sql
│   └── validation/                     # Data quality checks
│       ├── data_quality_checks.sql
│       └── row_counts.sql
│
├── dbt/                                # dbt transformation layer
│   ├── profiles.yml                   # dbt Snowflake profile
│   └── github_dbt/                    # dbt project
│       ├── dbt_project.yml            # dbt project configuration
│       ├── models/
│       │   ├── staging/               # Staging models
│       │   │   ├── stg_github_events.sql
│       │   │   └── stg_github_events.yml
│       │   └── marts/                 # Mart models
│       │       ├── dimensions/
│       │       │   ├── dim_actor.sql
│       │       │   ├── dim_repository.sql
│       │       │   └── dim_event_type.sql
│       │       └── facts/
│       │           ├── fact_events.sql
│       │           └── fact_push_events.sql
│       ├── macros/                    # dbt macros
│       ├── seeds/                     # Seed data
│       ├── snapshots/                 # Type-2 snapshots
│       └── tests/                     # dbt tests
│
├── dashboards/                         # Power BI assets
│   ├── powerbi/
│   │   └── github_analytics.pbix      # Power BI report
│   └── screenshots/                   # Dashboard screenshots
│
├── notebooks/                          # Jupyter notebooks for exploration
│   ├── schema_discovery.ipynb         # Explore raw data structure
│   ├── data_exploration.ipynb         # EDA and validation
│   └── event_analysis.ipynb           # Analytical investigations
│
├── scheduler/                          # Orchestration
│   ├── run_pipeline.bat               # Windows Task Scheduler script
│   ├── windows_task_scheduler.md      # Setup instructions
│   └── airflow/                       # (Future) Airflow DAGs
│       └── dags/
│           └── github_pipeline_dag.py # Orchestration workflow
│
├── docs/                               # Project documentation
│   ├── project_notes.md               # Development notes
│   ├── ARCHITECTURE.md                # Detailed architecture
│   ├── DATA_DICTIONARY.md             # Table/column documentation
│   └── SETUP_GUIDE.md                 # Environment setup
│
└── logs/                               # Application logs
    └── (*.log files created at runtime)
```

---

## 🚀 Quick Start

### Prerequisites

- **Python 3.11+**
- **Snowflake Account** (with adequate warehouse & storage)
- **dbt CLI** (installed via requirements.txt)
- **Snowflake Credentials** (user, password, account identifier)

### Setup

1. **Clone or create the project**
   ```bash
   cd c:\Users\abdul\Basith-Saas\DE\github-analytics-pipeline
   ```

2. **Create Python virtual environment**
   ```bash
   python -m venv venv
   venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment variables**
   ```bash
   cp .env .env.local  # Create local copy
   # Edit .env.local with your Snowflake credentials
   ```

5. **Test Snowflake connection**
   ```bash
   python -c "from ingestion.utils.snowflake_loader import SnowflakeLoader; print('Connection OK')"
   ```

---

## 📊 Project Phases

### ✅ Phase 1: Project Setup
- Project structure and configuration
- requirements.txt with all dependencies
- .env template for sensitive data
- Comprehensive README and documentation

### 📋 Phase 2: Snowflake Foundation
- Create GITHUB_DBT database with RAW, STAGING, MARTS schemas
- Create raw tables (GITHUB_EVENTS, LOAD_HISTORY)
- Create metadata tracking tables
- Validation scripts

### 🔌 Phase 3: GH Archive Ingestion Utilities
- `gharchive_client.py` - Download and validate files
- `snowflake_loader.py` - Batch loading with error handling
- `helpers.py` - Logging, date utilities, common functions

### 📥 Phase 4: Initial 7-Day Backfill
- `load_last_7_days.py` - Load YYYY-MM-DD-H files for past 7 days
- Prevent duplicate loads via LOAD_HISTORY tracking
- Validation: row counts, date ranges, event distributions

### ⏰ Phase 5: Incremental Hourly Loading
- `load_latest_hour.py` - Load most recent GH Archive file
- Check LOAD_HISTORY before processing
- Suitable for scheduled execution (hourly cron/Task Scheduler)

### 🔍 Phase 6: Raw Data Analysis
- SQL queries exploring event types, repositories, developers
- Identify data quality issues and patterns
- Foundation for dbt transformations

### 🧱 Phase 7: dbt Foundation
- Initialize dbt project
- Configure Snowflake profile (profiles.yml)
- Create sources.yml for documentation

### 🎯 Phase 8: Staging Models
- `stg_github_events.sql` - Flatten JSON, extract key fields
- Add dbt tests (uniqueness, null checks, accepted values)
- Document with schema.yml

### 💎 Phase 9: Dimensional Modeling
- **Dimensions**: dim_actor, dim_repository, dim_event_type
- **Facts**: fact_events, fact_push_events
- Design star schema with relationships
- Create ERD documentation

### ⚡ Phase 10: Incremental Transformations
- Convert fact tables to incremental models
- Process only new records daily/hourly
- Optimize for performance

### ✔️ Phase 11: Data Quality Framework
- dbt freshness tests
- Relationship tests between dimensions and facts
- Null, unique, and referential integrity checks
- Automated quality monitoring

### 📚 Phase 12: dbt Documentation
- Generate dbt documentation site with repo-local profile support
- Create lineage/model screenshot workflow
- Add data dictionary with business glossary
- Document dbt artifacts and troubleshooting steps

### 📊 Phase 13: Power BI Dashboard
- Connect to Snowflake marts
- Create KPI cards and visualizations
- Build interactive drill-down reports
- Publish production dashboard

### 🔄 Phase 14: Apache Airflow
- Create DAG: download → load → transform → test → publish
- Schedule hourly pipeline execution
- Implement monitoring and failure alerts
- Add backfill and recovery workflows

### 🎖️ Phase 15: Portfolio Readiness
- Update README with architecture diagrams
- Add project screenshots and metrics
- Create resume bullet points
- Document business impact and learnings

---

## 🛠️ Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Data Source** | GH Archive | GitHub events (7+ years of history) |
| **Ingestion** | Python 3.11+ | Download, validate, and load data |
| **Data Warehouse** | Snowflake | Centralized data storage (RAW → STAGING → MARTS) |
| **Transformation** | dbt | Data transformation, testing, documentation |
| **Orchestration** | Apache Airflow | Workflow scheduling and monitoring |
| **Analytics** | Power BI | Interactive dashboards and visualizations |
| **Notebooks** | Jupyter | Exploratory data analysis |

---

## 📈 Key Features

✅ **Idempotent Ingestion**: Deduplication via LOAD_HISTORY tracking  
✅ **Scalable Architecture**: Snowflake's unlimited scaling for petabyte data  
✅ **Version Control**: Full lineage via dbt  
✅ **Data Quality**: Automated tests at staging, dimensional, and fact layers  
✅ **Documentation**: Self-documenting via dbt and this README  
✅ **Incremental Processing**: Only process new data, minimize warehouse costs  
✅ **Error Resilience**: Comprehensive error handling and retry logic  
✅ **Production Ready**: Logging, monitoring, and alerting built-in  

---

## 🔐 Security

- ✅ Credentials stored in `.env` (not committed to git)
- ✅ Snowflake role-based access control (RBAC)
- ✅ No secrets in code or logs
- ✅ Support for Snowflake key pair authentication (future enhancement)

---

## 💰 Cost Optimization

- ✅ Incremental loads to minimize compute costs
- ✅ Snowflake warehouse auto-suspend configuration
- ✅ Columnar storage efficiency
- ✅ Partitioning by date for faster queries

---

## 📚 Documentation

- [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) - Environment setup instructions
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Detailed system architecture
- [DATA_DICTIONARY.md](docs/DATA_DICTIONARY.md) - Table and column definitions
- [PHASE12_DBT_DOCS.md](docs/PHASE12_DBT_DOCS.md) - dbt docs, lineage, and screenshot workflow
- [dbt-lineage.png](docs/screenshots/dbt-lineage.png) - dbt docs overview/lineage entry point
- [dbt-fact_events.png](docs/screenshots/dbt-fact_events.png) - fact model documentation screenshot
- [dbt-dim_actor.png](docs/screenshots/dbt-dim_actor.png) - actor dimension documentation screenshot
- [project_notes.md](docs/project_notes.md) - Development decisions and lessons learned

---

## 🤝 Contributing

This is a portfolio project demonstrating enterprise data engineering. For modifications:

1. Create a feature branch
2. Make changes with test coverage
3. Update documentation
4. Submit for review

---

## 📞 Support

For issues or questions:
- Check documentation in `/docs` folder
- Review logs in `/logs` folder
- Examine dbt artifacts in `/dbt/target` folder

---

## 📝 License

Portfolio project - for demonstration and learning purposes.

---

**Last Updated**: June 2026  
**Status**: 🚀 In Development  
**Current Phase**: 13 - Power BI Dashboard
