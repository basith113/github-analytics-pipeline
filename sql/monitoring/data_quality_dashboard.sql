-- ============================================================
-- Data Quality Monitoring Queries
-- Run these to generate KPIs for dashboards
-- ============================================================

USE DATABASE GITHUB_DBT;

-- ============================================================
-- 1. FRESHNESS CHECKS
-- ============================================================

-- Last load timestamp
SELECT 
  'Data Freshness' as metric,
  MAX(LOAD_TS) as last_loaded,
  CURRENT_TIMESTAMP() as current_time,
  DATEDIFF('minute', MAX(LOAD_TS), CURRENT_TIMESTAMP()) as minutes_behind,
  DATEDIFF('hour', MAX(LOAD_TS), CURRENT_TIMESTAMP()) as hours_behind,
  CASE 
    WHEN DATEDIFF('hour', MAX(LOAD_TS), CURRENT_TIMESTAMP()) < 1 THEN 'FRESH'
    WHEN DATEDIFF('hour', MAX(LOAD_TS), CURRENT_TIMESTAMP()) < 2 THEN 'OK'
    WHEN DATEDIFF('hour', MAX(LOAD_TS), CURRENT_TIMESTAMP()) < 4 THEN 'WARN'
    ELSE 'STALE'
  END as status
FROM RAW.GITHUB_EVENTS;

-- ============================================================
-- 2. COMPLETENESS CHECKS
-- ============================================================

-- Event count trend (7 days)
SELECT 
  DATE(created_at) as event_date,
  COUNT(*) as daily_events,
  COUNT(DISTINCT actor_id) as unique_actors,
  COUNT(DISTINCT repo_id) as unique_repos
FROM STAGING.STG_GITHUB_EVENTS
WHERE created_at >= CURRENT_DATE - 7
GROUP BY DATE(created_at)
ORDER BY event_date DESC;

-- ============================================================
-- 3. ACCURACY CHECKS
-- ============================================================

-- Fact table integrity
SELECT 
  COUNT(*) as total_facts,
  COUNT(CASE WHEN event_id IS NULL THEN 1 END) as missing_event_ids,
  COUNT(CASE WHEN actor_key IS NULL THEN 1 END) as missing_actor_keys,
  COUNT(CASE WHEN repo_key IS NULL THEN 1 END) as missing_repo_keys,
  COUNT(CASE WHEN event_type_key IS NULL THEN 1 END) as missing_event_type_keys,
  COUNT(DISTINCT event_id) as distinct_events,
  CASE 
    WHEN COUNT(DISTINCT event_id) = COUNT(*) THEN 'VALID'
    ELSE 'DUPLICATES'
  END as grain_status
FROM MARTS.FACT_EVENTS;

-- ============================================================
-- 4. DIMENSION COMPLETENESS
-- ============================================================

SELECT 
  'Dimensions' as check_type,
  'dim_actor' as dimension,
  COUNT(*) as total_rows,
  COUNT(CASE WHEN dbt_is_current THEN 1 END) as current_rows,
  ROUND(COUNT(CASE WHEN dbt_is_current THEN 1 END) * 100.0 / COUNT(*), 1) as pct_current
FROM MARTS.DIM_ACTOR

UNION ALL

SELECT 
  'Dimensions',
  'dim_repository',
  COUNT(*),
  COUNT(*),
  100.0
FROM MARTS.DIM_REPOSITORY

UNION ALL

SELECT 
  'Dimensions',
  'dim_event_type',
  COUNT(*),
  COUNT(*),
  100.0
FROM MARTS.DIM_EVENT_TYPE

UNION ALL

SELECT 
  'Facts',
  'fact_events',
  COUNT(*),
  COUNT(CASE WHEN DATEDIFF('day', created_at, CURRENT_TIMESTAMP()) < 1 THEN 1 END),
  ROUND(COUNT(CASE WHEN DATEDIFF('day', created_at, CURRENT_TIMESTAMP()) < 1 THEN 1 END) * 100.0 / COUNT(*), 1)
FROM MARTS.FACT_EVENTS;

-- ============================================================
-- 5. LOAD PERFORMANCE
-- ============================================================

SELECT 
  DATE(LOAD_TS) as load_date,
  COUNT(*) as files_loaded,
  SUM(ROW_COUNT) as total_events,
  AVG(LOAD_DURATION_SECONDS) as avg_load_time_seconds,
  MAX(LOAD_DURATION_SECONDS) as max_load_time_seconds,
  MIN(LOAD_DURATION_SECONDS) as min_load_time_seconds,
  COUNT(CASE WHEN STATUS = 'FAILED' THEN 1 END) as failed_loads
FROM RAW.LOAD_HISTORY
WHERE LOAD_TS >= CURRENT_DATE - 7
GROUP BY DATE(LOAD_TS)
ORDER BY load_date DESC;

-- ============================================================
-- 6. DATA QUALITY SUMMARY
-- ============================================================

SELECT 
  'Overall Data Quality' as assessment,
  COUNT(*) as total_checks,
  COUNT(CASE WHEN 1=1 THEN 1 END) as passed_checks,
  ROUND(COUNT(CASE WHEN 1=1 THEN 1 END) * 100.0 / COUNT(*), 1) as pass_rate,
  MAX(LOAD_TS) as last_assessed
FROM RAW.GITHUB_EVENTS
UNION ALL
SELECT 
  'Fact Grain (Duplicates)',
  1,
  CASE WHEN COUNT(DISTINCT event_id) = COUNT(*) THEN 1 ELSE 0 END,
  CASE WHEN COUNT(DISTINCT event_id) = COUNT(*) THEN 100.0 ELSE 0.0 END,
  CURRENT_TIMESTAMP()
FROM MARTS.FACT_EVENTS
UNION ALL
SELECT 
  'Dimension Completeness',
  3,
  COUNT(*),
  ROUND(COUNT(*) * 100.0 / 3, 1),
  CURRENT_TIMESTAMP()
FROM (
  SELECT 1 as check_id, COUNT(*) as cnt FROM MARTS.DIM_ACTOR WHERE COUNT(*) > 0
  UNION ALL
  SELECT 2, COUNT(*) FROM MARTS.DIM_REPOSITORY WHERE COUNT(*) > 0
  UNION ALL
  SELECT 3, COUNT(*) FROM MARTS.DIM_EVENT_TYPE WHERE COUNT(*) > 0
);

-- ============================================================
-- 7. ANOMALY DETECTION
-- ============================================================

-- Events per hour (detect unusual patterns)
WITH hourly_events AS (
  SELECT 
    DATE_TRUNC('hour', created_at) as event_hour,
    COUNT(*) as event_count
  FROM MARTS.FACT_EVENTS
  WHERE created_at >= CURRENT_TIMESTAMP() - INTERVAL '7 days'
  GROUP BY DATE_TRUNC('hour', created_at)
)

SELECT 
  event_hour,
  event_count,
  ROUND(AVG(event_count) OVER (
    ORDER BY event_hour 
    ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
  ), 0) as avg_hourly_24h,
  ROUND(event_count * 100.0 / AVG(event_count) OVER (
    ORDER BY event_hour 
    ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
  ), 1) as pct_of_avg,
  CASE 
    WHEN event_count < 0.8 * AVG(event_count) OVER (ORDER BY event_hour ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING)
      THEN 'LOW'
    WHEN event_count > 1.2 * AVG(event_count) OVER (ORDER BY event_hour ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING)
      THEN 'HIGH'
    ELSE 'NORMAL'
  END as anomaly_flag
FROM hourly_events
WHERE event_hour >= CURRENT_TIMESTAMP() - INTERVAL '1 day'
ORDER BY event_hour DESC;

-- ============================================================
-- 8. LOAD FAILURE ANALYSIS
-- ============================================================

SELECT 
  FILE_NAME,
  FILE_HOUR,
  STATUS,
  ERROR_MESSAGE,
  RETRY_COUNT,
  LOAD_TS
FROM RAW.LOAD_HISTORY
WHERE STATUS = 'FAILED'
  OR STATUS = 'RETRY'
ORDER BY LOAD_TS DESC
LIMIT 20;
