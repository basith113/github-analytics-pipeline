-- ============================================================
-- GitHub Analytics Pipeline - Load History Setup & Utilities
-- Phase 2: Snowflake Foundation (Supplementary)
-- ============================================================
--
-- Purpose: Utility scripts for managing load history and
-- preventing duplicate file loads
--
-- Contains:
--   - Utility procedures
--   - Monitoring queries
--   - Data quality checks
--   - Cleanup procedures
--
-- ============================================================

USE DATABASE GITHUB_DBT;
USE SCHEMA RAW;

-- ============================================================
-- 1. Utility Procedures
-- ============================================================

-- Procedure: Record successful file load
CREATE OR REPLACE PROCEDURE RECORD_FILE_LOAD(
  P_FILE_NAME VARCHAR,
  P_FILE_HOUR TIMESTAMP_NTZ,
  P_ROW_COUNT INT,
  P_LOAD_DURATION_SECONDS DECIMAL
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
  INSERT INTO LOAD_HISTORY (
    FILE_NAME,
    FILE_HOUR,
    ROW_COUNT,
    STATUS,
    LOAD_DURATION_SECONDS,
    LOADED_BY
  ) VALUES (
    P_FILE_NAME,
    P_FILE_HOUR,
    P_ROW_COUNT,
    'SUCCESS',
    P_LOAD_DURATION_SECONDS,
    CURRENT_USER()
  );
  
  RETURN 'File load recorded: ' || P_FILE_NAME;
EXCEPTION WHEN OTHER THEN
  RETURN 'Error recording file: ' || SQLERRM;
END;
$$;

-- Procedure: Record failed file load
CREATE OR REPLACE PROCEDURE RECORD_FILE_LOAD_FAILURE(
  P_FILE_NAME VARCHAR,
  P_FILE_HOUR TIMESTAMP_NTZ,
  P_ERROR_MESSAGE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
  INSERT INTO LOAD_HISTORY (
    FILE_NAME,
    FILE_HOUR,
    ROW_COUNT,
    STATUS,
    ERROR_MESSAGE,
    LOADED_BY
  ) VALUES (
    P_FILE_NAME,
    P_FILE_HOUR,
    0,
    'FAILED',
    P_ERROR_MESSAGE,
    CURRENT_USER()
  );
  
  RETURN 'Failure recorded: ' || P_FILE_NAME;
EXCEPTION WHEN OTHER THEN
  RETURN 'Error recording failure: ' || SQLERRM;
END;
$$;

-- ============================================================
-- 2. Monitoring Queries
-- ============================================================

-- Query: Total events loaded by hour
SELECT 
  DATE_TRUNC('hour', FILE_HOUR) AS LOAD_HOUR,
  COUNT(*) AS FILES_LOADED,
  SUM(ROW_COUNT) AS TOTAL_ROWS
FROM LOAD_HISTORY
WHERE STATUS = 'SUCCESS'
GROUP BY DATE_TRUNC('hour', FILE_HOUR)
ORDER BY LOAD_HOUR DESC;

-- Query: Load distribution by status
SELECT 
  STATUS,
  COUNT(*) AS FILE_COUNT,
  SUM(ROW_COUNT) AS TOTAL_ROWS,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM LOAD_HISTORY), 2) AS PERCENTAGE
FROM LOAD_HISTORY
GROUP BY STATUS
ORDER BY FILE_COUNT DESC;

-- Query: Average load time by status
SELECT 
  STATUS,
  COUNT(*) AS ATTEMPT_COUNT,
  ROUND(AVG(LOAD_DURATION_SECONDS), 2) AS AVG_DURATION_SECONDS,
  MIN(LOAD_DURATION_SECONDS) AS MIN_DURATION_SECONDS,
  MAX(LOAD_DURATION_SECONDS) AS MAX_DURATION_SECONDS
FROM LOAD_HISTORY
WHERE LOAD_DURATION_SECONDS IS NOT NULL
GROUP BY STATUS;

-- Query: Files that need retry
SELECT 
  FILE_NAME,
  FILE_HOUR,
  STATUS,
  RETRY_COUNT,
  ERROR_MESSAGE,
  LOAD_TS
FROM LOAD_HISTORY
WHERE STATUS IN ('FAILED', 'RETRY')
  AND LOAD_TS >= CURRENT_TIMESTAMP() - INTERVAL '7 days'
ORDER BY LOAD_TS DESC;

-- Query: Data freshness check (when was last successful load?)
SELECT 
  MAX(FILE_HOUR) AS LATEST_LOADED_HOUR,
  MAX(LOAD_TS) AS LOAD_TIMESTAMP,
  DATEDIFF('hour', MAX(FILE_HOUR), CURRENT_TIMESTAMP()) AS HOURS_BEHIND
FROM LOAD_HISTORY
WHERE STATUS = 'SUCCESS';

-- ============================================================
-- 3. Data Quality Queries
-- ============================================================

-- Query: Detect missing hours (gaps in loading)
WITH hourly_sequence AS (
  SELECT GENERATE_SERIES(
    DATE_TRUNC('hour', (SELECT MIN(FILE_HOUR) FROM LOAD_HISTORY)),
    CURRENT_TIMESTAMP(),
    '1 hour'::INTERVAL
  ) AS expected_hour
)
SELECT 
  hs.expected_hour,
  CASE 
    WHEN lh.FILE_NAME IS NULL THEN 'MISSING'
    WHEN lh.STATUS != 'SUCCESS' THEN 'FAILED'
    ELSE 'LOADED'
  END AS status,
  lh.FILE_NAME,
  lh.ROW_COUNT
FROM hourly_sequence hs
LEFT JOIN LOAD_HISTORY lh ON DATE_TRUNC('hour', lh.FILE_HOUR) = hs.expected_hour
WHERE hs.expected_hour >= CURRENT_TIMESTAMP() - INTERVAL '30 days'
  AND status != 'LOADED'
ORDER BY hs.expected_hour DESC;

-- Query: Detect unusual row counts (anomalies)
WITH stats AS (
  SELECT 
    ROW_COUNT,
    AVG(ROW_COUNT) OVER () AS avg_rows,
    STDDEV(ROW_COUNT) OVER () AS stddev_rows
  FROM LOAD_HISTORY
  WHERE STATUS = 'SUCCESS'
    AND ROW_COUNT > 0
)
SELECT DISTINCT
  FILE_NAME,
  FILE_HOUR,
  ROW_COUNT,
  ROUND(avg_rows, 0) AS expected_avg,
  CASE 
    WHEN ROW_COUNT < (avg_rows - 2 * stddev_rows) THEN 'LOW'
    WHEN ROW_COUNT > (avg_rows + 2 * stddev_rows) THEN 'HIGH'
    ELSE 'NORMAL'
  END AS anomaly
FROM stats
WHERE ROW_COUNT > 0
  AND ABS(ROW_COUNT - avg_rows) > 2 * stddev_rows
ORDER BY FILE_HOUR DESC;

-- ============================================================
-- 4. Cleanup Procedures (Use with caution!)
-- ============================================================

-- Procedure: Archive old successful loads (optional)
CREATE OR REPLACE PROCEDURE ARCHIVE_OLD_LOADS(
  P_DAYS_TO_KEEP INT DEFAULT 90
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
  archived_count INT;
BEGIN
  -- Count records to archive
  archived_count := (
    SELECT COUNT(*) FROM LOAD_HISTORY
    WHERE STATUS = 'SUCCESS'
      AND LOAD_TS < CURRENT_TIMESTAMP() - INTERVAL || P_DAYS_TO_KEEP || ' days'
  );
  
  -- Archive (in real implementation, copy to archive table first)
  DELETE FROM LOAD_HISTORY
  WHERE STATUS = 'SUCCESS'
    AND LOAD_TS < CURRENT_TIMESTAMP() - INTERVAL || P_DAYS_TO_KEEP || ' days';
  
  RETURN 'Archived ' || archived_count || ' old load records';
EXCEPTION WHEN OTHER THEN
  RETURN 'Archive failed: ' || SQLERRM;
END;
$$;

-- ============================================================
-- 5. Integration Queries for Python
-- ============================================================

-- Query: Get all unloaded hours
CREATE OR REPLACE VIEW UNLOADED_HOURS AS
WITH date_range AS (
  SELECT 
    DATEADD('hour', -744, DATE_TRUNC('hour', CURRENT_TIMESTAMP())) AS start_time,  -- Last 31 days
    CURRENT_TIMESTAMP() AS end_time
),
all_hours AS (
  SELECT GENERATE_SERIES(
    (SELECT start_time FROM date_range),
    (SELECT end_time FROM date_range),
    '1 hour'::INTERVAL
  ) AS hour_value
)
SELECT 
  ah.hour_value,
  YEAR(ah.hour_value) || '-' || 
  LPAD(MONTH(ah.hour_value), 2, '0') || '-' || 
  LPAD(DAY(ah.hour_value), 2, '0') || '-' || 
  LPAD(HOUR(ah.hour_value), 2, '0') AS expected_file_name
FROM all_hours ah
LEFT JOIN LOAD_HISTORY lh ON DATE_TRUNC('hour', lh.FILE_HOUR) = ah.hour_value
WHERE lh.FILE_NAME IS NULL
ORDER BY ah.hour_value DESC;

COMMENT ON VIEW UNLOADED_HOURS IS 'Hours that have not been loaded yet';

-- Query: Get last N successfully loaded files
CREATE OR REPLACE VIEW LAST_LOADED_FILES AS
SELECT TOP 24
  FILE_NAME,
  FILE_HOUR,
  ROW_COUNT,
  LOAD_DURATION_SECONDS,
  LOAD_TS
FROM LOAD_HISTORY
WHERE STATUS = 'SUCCESS'
ORDER BY FILE_HOUR DESC;

COMMENT ON VIEW LAST_LOADED_FILES IS 'Last 24 successfully loaded files';

-- ============================================================
-- 6. Verification
-- ============================================================

-- Display summary of load history setup
SELECT 
  'Load History Utilities Setup Complete' AS Status,
  CURRENT_TIMESTAMP() AS Timestamp,
  'Procedures, views, and queries created' AS Details;
