-- ============================================================
-- Phase 6: Raw Data Analysis Queries
-- GitHub Analytics Pipeline
-- ============================================================
--
-- Purpose: Analyze raw GitHub events data to understand:
--   - Data quality and completeness
--   - Event type distribution
--   - Most active repositories
--   - Most active developers
--   - Daily trends
--   - Potential data issues
--
-- Run these queries AFTER Phase 4 (backfill) completes
-- Database: GITHUB_DBT.RAW
-- 
-- Expected result: ~2-2.5M events from past 7 days
--
-- ============================================================

USE DATABASE GITHUB_DBT;
USE SCHEMA RAW;

-- ============================================================
-- 1. Data Completeness Check
-- ============================================================

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

-- Null checks
SELECT 
  'id' as field,
  COUNT(CASE WHEN RAW_DATA:id IS NULL THEN 1 END) as null_count,
  ROUND(COUNT(CASE WHEN RAW_DATA:id IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as null_percent
FROM GITHUB_EVENTS
UNION ALL
SELECT 'type', COUNT(CASE WHEN RAW_DATA:type IS NULL THEN 1 END), 
  ROUND(COUNT(CASE WHEN RAW_DATA:type IS NULL THEN 1 END) * 100.0 / COUNT(*), 2)
FROM GITHUB_EVENTS
UNION ALL
SELECT 'actor', COUNT(CASE WHEN RAW_DATA:actor IS NULL THEN 1 END),
  ROUND(COUNT(CASE WHEN RAW_DATA:actor IS NULL THEN 1 END) * 100.0 / COUNT(*), 2)
FROM GITHUB_EVENTS
UNION ALL
SELECT 'repo', COUNT(CASE WHEN RAW_DATA:repo IS NULL THEN 1 END),
  ROUND(COUNT(CASE WHEN RAW_DATA:repo IS NULL THEN 1 END) * 100.0 / COUNT(*), 2)
FROM GITHUB_EVENTS
UNION ALL
SELECT 'created_at', COUNT(CASE WHEN RAW_DATA:created_at IS NULL THEN 1 END),
  ROUND(COUNT(CASE WHEN RAW_DATA:created_at IS NULL THEN 1 END) * 100.0 / COUNT(*), 2)
FROM GITHUB_EVENTS
ORDER BY null_count DESC;

-- ============================================================
-- 2. Event Type Distribution (sql/analysis/event_type_distribution.sql)
-- ============================================================

SELECT 
  RAW_DATA:type as event_type,
  COUNT(*) as event_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percent_of_total,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repos
FROM GITHUB_EVENTS
GROUP BY RAW_DATA:type
ORDER BY event_count DESC;

-- ============================================================
-- 3. Top Repositories (sql/analysis/top_repositories.sql)
-- ============================================================

SELECT 
  RAW_DATA:repo:id as repo_id,
  RAW_DATA:repo:name as repo_name,
  COUNT(*) as event_count,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_actors,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  MIN(RAW_DATA:created_at) as first_event,
  MAX(RAW_DATA:created_at) as last_event,
  ARRAY_UNIQUE_AGG(RAW_DATA:type) as event_type_list
FROM GITHUB_EVENTS
GROUP BY RAW_DATA:repo:id, RAW_DATA:repo:name
ORDER BY event_count DESC
LIMIT 50;

-- ============================================================
-- 4. Top Developers (sql/analysis/top_developers.sql)
-- ============================================================

SELECT 
  RAW_DATA:actor:id as actor_id,
  RAW_DATA:actor:login as actor_login,
  RAW_DATA:actor:type as actor_type,
  COUNT(*) as event_count,
  COUNT(DISTINCT RAW_DATA:repo:id) as repos_contributed,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  MIN(RAW_DATA:created_at) as first_event,
  MAX(RAW_DATA:created_at) as last_event
FROM GITHUB_EVENTS
GROUP BY RAW_DATA:actor:id, RAW_DATA:actor:login, RAW_DATA:actor:type
ORDER BY event_count DESC
LIMIT 50;

-- ============================================================
-- 5. Daily Activity Trend (sql/analysis/daily_activity.sql)
-- ============================================================

SELECT 
  DATE(RAW_DATA:created_at) as event_date,
  COUNT(*) as daily_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as daily_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as daily_repos,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  ROUND(COUNT(*) / 24.0, 0) as avg_events_per_hour
FROM GITHUB_EVENTS
GROUP BY DATE(RAW_DATA:created_at)
ORDER BY event_date DESC;

-- ============================================================
-- 6. Hourly Activity Pattern
-- ============================================================

-- Find peak hours across all days
SELECT 
  HOUR(RAW_DATA:created_at) as utc_hour,
  COUNT(*) as total_events,
  ROUND(COUNT(*) / 7.0, 0) as avg_per_day,  -- Assuming 7 days of data
  COUNT(DISTINCT RAW_DATA:actor:id) as total_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as total_repos
FROM GITHUB_EVENTS
GROUP BY HOUR(RAW_DATA:created_at)
ORDER BY total_events DESC;

-- ============================================================
-- 7. Repository Language Distribution
-- ============================================================

-- Note: language is not always present; this shows availability
SELECT 
  RAW_DATA:repo:language as language,
  COUNT(*) as event_count,
  COUNT(DISTINCT RAW_DATA:repo:id) as repo_count
FROM GITHUB_EVENTS
WHERE RAW_DATA:repo:language IS NOT NULL
GROUP BY RAW_DATA:repo:language
ORDER BY event_count DESC
LIMIT 30;

-- ============================================================
-- 8. File Load Statistics
-- ============================================================

SELECT 
  DATE_TRUNC('day', FILE_HOUR) as load_date,
  COUNT(*) as files_loaded,
  SUM(ROW_COUNT) as total_events,
  AVG(ROW_COUNT) as avg_events_per_file,
  MIN(ROW_COUNT) as min_events,
  MAX(ROW_COUNT) as max_events,
  ROUND(AVG(LOAD_DURATION_SECONDS), 2) as avg_load_time
FROM LOAD_HISTORY
WHERE STATUS = 'SUCCESS'
GROUP BY DATE_TRUNC('day', FILE_HOUR)
ORDER BY load_date DESC;

-- ============================================================
-- 9. Event Rate Analysis
-- ============================================================

-- Events per minute
WITH events_by_minute AS (
  SELECT 
    DATE_TRUNC('minute', RAW_DATA:created_at) as minute,
    COUNT(*) as event_count
  FROM GITHUB_EVENTS
  GROUP BY DATE_TRUNC('minute', RAW_DATA:created_at)
)
SELECT 
  MIN(event_count) as min_per_minute,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY event_count) as p25_per_minute,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY event_count) as median_per_minute,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY event_count) as p75_per_minute,
  MAX(event_count) as max_per_minute,
  ROUND(AVG(event_count), 2) as avg_per_minute
FROM events_by_minute;

-- ============================================================
-- 10. Data Quality Report
-- ============================================================

SELECT 
  'Raw Data Quality Report' as report,
  CURRENT_TIMESTAMP() as generated_at
UNION ALL
SELECT '', ''
UNION ALL
SELECT '1. Coverage:', ''
UNION ALL
SELECT '  Total Events', COUNT(*)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Date Range', MIN(RAW_DATA:created_at)::VARCHAR || ' to ' || MAX(RAW_DATA:created_at)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '', ''
UNION ALL
SELECT '2. Data Completeness:', ''
UNION ALL
SELECT '  Missing Event IDs', COUNT(CASE WHEN RAW_DATA:id IS NULL THEN 1 END)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Missing Event Types', COUNT(CASE WHEN RAW_DATA:type IS NULL THEN 1 END)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Missing Actors', COUNT(CASE WHEN RAW_DATA:actor IS NULL THEN 1 END)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Missing Repos', COUNT(CASE WHEN RAW_DATA:repo IS NULL THEN 1 END)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '', ''
UNION ALL
SELECT '3. Entity Counts:', ''
UNION ALL
SELECT '  Unique Developers', COUNT(DISTINCT RAW_DATA:actor:id)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Unique Repositories', COUNT(DISTINCT RAW_DATA:repo:id)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '  Event Types', COUNT(DISTINCT RAW_DATA:type)::VARCHAR FROM GITHUB_EVENTS
UNION ALL
SELECT '', ''
UNION ALL
SELECT '4. Load Status:', ''
UNION ALL
SELECT '  Files Loaded', COUNT(*)::VARCHAR FROM LOAD_HISTORY WHERE STATUS = 'SUCCESS'
UNION ALL
SELECT '  Load Failures', COUNT(*)::VARCHAR FROM LOAD_HISTORY WHERE STATUS = 'FAILED';

-- ============================================================
-- 11. Data Anomalies
-- ============================================================

-- Files with unusually low or high event counts
WITH file_stats AS (
  SELECT 
    AVG(ROW_COUNT) as avg_rows,
    STDDEV(ROW_COUNT) as stddev_rows
  FROM LOAD_HISTORY
  WHERE STATUS = 'SUCCESS' AND ROW_COUNT > 0
)
SELECT 
  lh.FILE_NAME,
  lh.ROW_COUNT,
  ROUND((SELECT avg_rows FROM file_stats), 0) as expected_avg,
  CASE 
    WHEN lh.ROW_COUNT < ((SELECT avg_rows FROM file_stats) - 2 * (SELECT stddev_rows FROM file_stats)) THEN 'LOW'
    WHEN lh.ROW_COUNT > ((SELECT avg_rows FROM file_stats) + 2 * (SELECT stddev_rows FROM file_stats)) THEN 'HIGH'
    ELSE 'NORMAL'
  END as anomaly_flag
FROM LOAD_HISTORY lh
WHERE lh.STATUS = 'SUCCESS'
ORDER BY lh.ROW_COUNT ASC;

-- ============================================================
-- 12. Export Raw Sample Data (for inspection)
-- ============================================================

-- Sample 10 raw events
SELECT 
  RAW_DATA::STRING as raw_json
FROM GITHUB_EVENTS
LIMIT 10;