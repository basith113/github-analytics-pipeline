-- Daily Activity Analysis
-- Shows trends in GitHub events over time

USE DATABASE GITHUB_DBT;

SELECT 
  DATE(RAW_DATA:created_at) as activity_date,
  COUNT(*) as daily_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_developers,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repositories,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  ROUND(COUNT(*) / 24.0, 0) as avg_events_per_hour,
  MIN(RAW_DATA:created_at) as earliest_event,
  MAX(RAW_DATA:created_at) as latest_event
FROM RAW.GITHUB_EVENTS
GROUP BY DATE(RAW_DATA:created_at)
ORDER BY activity_date DESC;