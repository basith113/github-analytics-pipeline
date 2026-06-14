-- ============================================================
-- GitHub Analytics Pipeline - Raw Table Setup
-- Phase 2: Snowflake Foundation
-- ============================================================
--
-- Purpose: Create raw tables to store unprocessed GitHub events
-- from GH Archive.
--
-- Tables:
--   1. GITHUB_EVENTS: Raw event data (JSON variant)
--   2. LOAD_HISTORY: Metadata tracking for deduplication
--
-- Key Design Decisions:
--   - Use VARIANT for raw JSON (flexible, future-proof)
--   - Minimal transformation (only decompression)
--   - Track file source and load timestamp for auditing
--
-- ============================================================

USE DATABASE GITHUB_DBT;
USE SCHEMA RAW;

-- ============================================================
-- 1. Create GITHUB_EVENTS Table
-- ============================================================
--
-- Stores raw GitHub events exactly as received from GH Archive
-- One row per event (many rows per file)
--
-- Schema:
--   - RAW_DATA: Full JSON object from GH Archive
--   - FILE_NAME: Source file name (YYYY-MM-DD-H.json.gz)
--   - LOAD_TS: Timestamp when record was loaded
--
-- Rationale for VARIANT type:
--   ✅ Flexible: Can store JSON without predefined schema
--   ✅ Future-proof: No need to alter table if GH API changes
--   ✅ Performant: Snowflake optimizes variant queries
--   ✅ Auditable: Can inspect raw data for debugging
--
-- Sample GH Archive Event:
-- {
--   "id": 12345678901,
--   "type": "PushEvent",
--   "actor": {"id": 1234567, "login": "octocat", ...},
--   "repo": {"id": 1296269, "name": "octocat/Hello-World", ...},
--   "payload": {"ref": "refs/heads/main", "before": "...", ...},
--   "public": true,
--   "created_at": "2024-01-15T10:30:00Z"
-- }

CREATE TABLE IF NOT EXISTS GITHUB_EVENTS (
  -- Core columns
  RAW_DATA VARIANT NOT NULL,                          -- Full JSON event from GH Archive
  FILE_NAME VARCHAR(50) NOT NULL,                    -- Source file: YYYY-MM-DD-H.json.gz
  LOAD_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), -- When row was loaded
  
  -- System columns for performance
  _INSERTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  _FILE_ROW_NUMBER INT                                -- Row number within file (for debugging)
)
COMMENT = 'Raw GitHub events stored as JSON from GH Archive - no transformations applied'
DATA_RETENTION_TIME_IN_DAYS = 1;

-- Create indexes for common query patterns
-- Note: Snowflake uses clustering instead of traditional indexes

-- Cluster by LOAD_TS for time-range queries
ALTER TABLE GITHUB_EVENTS 
  CLUSTER BY (LOAD_TS);

-- ============================================================
-- 2. Create LOAD_HISTORY Table
-- ============================================================
--
-- Metadata table tracking which files have been loaded
-- Prevents duplicate loads (idempotency guarantee)
--
-- Grain: One row per file loaded
--
-- Usage:
--   - Before loading: Check if file already exists
--   - After loading: Insert record to mark as complete
--   - Monitoring: Query to see load patterns and issues
--

CREATE TABLE IF NOT EXISTS LOAD_HISTORY (
  -- Primary key
  FILE_NAME VARCHAR(50) NOT NULL,                    -- e.g., "2024-01-15-3.json.gz"
  
  -- Timestamps
  LOAD_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), -- When file was loaded
  FILE_HOUR TIMESTAMP_NTZ NOT NULL,                 -- Hour represented by file
  
  -- Load details
  ROW_COUNT INT NOT NULL,                            -- Number of events in file
  FILE_SIZE_BYTES INT,                               -- Size of compressed file (optional)
  
  -- Status tracking
  STATUS VARCHAR(20) NOT NULL,                       -- SUCCESS, FAILED, SKIPPED, RETRY
  ERROR_MESSAGE VARCHAR(1000),                       -- If STATUS = FAILED
  RETRY_COUNT INT DEFAULT 0,                         -- Number of retry attempts
  
  -- Performance metadata
  LOAD_DURATION_SECONDS DECIMAL(10,2),              -- Time to load file
  PROCESSING_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  
  -- Audit trail
  LOADED_BY VARCHAR(255),                            -- User/process that loaded file
  
  -- Constraints
  PRIMARY KEY (FILE_NAME)
)
COMMENT = 'Tracks loaded files to prevent duplicates and provide audit trail'
DATA_RETENTION_TIME_IN_DAYS = 90;  -- Keep longer for historical tracking

-- Create indexes for common queries
ALTER TABLE LOAD_HISTORY 
  CLUSTER BY (FILE_HOUR, STATUS);

-- ============================================================
-- 3. Create Views for Monitoring
-- ============================================================

-- View: Recently loaded files
CREATE OR REPLACE VIEW LOAD_HISTORY_RECENT AS
SELECT 
  FILE_NAME,
  FILE_HOUR,
  ROW_COUNT,
  STATUS,
  LOAD_DURATION_SECONDS,
  LOAD_TS
FROM LOAD_HISTORY
WHERE LOAD_TS >= CURRENT_TIMESTAMP() - INTERVAL '7 days'
ORDER BY LOAD_TS DESC;

COMMENT ON VIEW LOAD_HISTORY_RECENT IS 'Recently loaded files (past 7 days)';

-- View: Load failures for investigation
CREATE OR REPLACE VIEW LOAD_HISTORY_FAILURES AS
SELECT 
  FILE_NAME,
  FILE_HOUR,
  STATUS,
  ERROR_MESSAGE,
  RETRY_COUNT,
  LOAD_TS
FROM LOAD_HISTORY
WHERE STATUS IN ('FAILED', 'RETRY')
ORDER BY LOAD_TS DESC;

COMMENT ON VIEW LOAD_HISTORY_FAILURES IS 'Failed load attempts for debugging';

-- View: Daily load summary
CREATE OR REPLACE VIEW LOAD_HISTORY_DAILY_SUMMARY AS
SELECT 
  DATE_TRUNC('day', FILE_HOUR) AS LOAD_DATE,
  COUNT(*) AS FILES_LOADED,
  COUNT(CASE WHEN STATUS = 'SUCCESS' THEN 1 END) AS SUCCESS_COUNT,
  COUNT(CASE WHEN STATUS IN ('FAILED', 'RETRY') THEN 1 END) AS FAILED_COUNT,
  SUM(ROW_COUNT) AS TOTAL_ROWS_LOADED,
  AVG(LOAD_DURATION_SECONDS) AS AVG_LOAD_TIME_SECONDS,
  MAX(LOAD_TS) AS LAST_LOAD_TIME
FROM LOAD_HISTORY
GROUP BY DATE_TRUNC('day', FILE_HOUR)
ORDER BY LOAD_DATE DESC;

COMMENT ON VIEW LOAD_HISTORY_DAILY_SUMMARY IS 'Daily aggregated load statistics';

-- ============================================================
-- 4. Create Stored Procedures (Optional, for Phase 5)
-- ============================================================

-- Procedure: Check if file already loaded
CREATE OR REPLACE PROCEDURE CHECK_FILE_LOADED(FILE_NAME_VAR VARCHAR)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
SELECT COUNT(*) > 0 
FROM LOAD_HISTORY 
WHERE FILE_NAME = FILE_NAME_VAR AND STATUS = 'SUCCESS';
$$;

COMMENT ON PROCEDURE CHECK_FILE_LOADED(VARCHAR) IS 'Check if file has already been loaded';

-- ============================================================
-- 5. Verification Queries
-- ============================================================

-- Verify tables exist
SHOW TABLES IN SCHEMA RAW;

-- Check table structure
DESC TABLE GITHUB_EVENTS;
DESC TABLE LOAD_HISTORY;

-- Display summary
SELECT 
  'Raw Data Tables Setup Complete' AS Status,
  CURRENT_TIMESTAMP() AS Timestamp,
  'GITHUB_EVENTS, LOAD_HISTORY created' AS Details;