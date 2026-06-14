-- Top Repositories Analysis
-- Identifies most active repositories in raw event data

USE DATABASE GITHUB_DBT;

SELECT 
  RAW_DATA:repo:id as repo_id,
  RAW_DATA:repo:name as repo_name,
  COUNT(*) as total_events,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_contributors,
  COUNT(DISTINCT RAW_DATA:type) as event_type_count,
  MIN(RAW_DATA:created_at) as first_event,
  MAX(RAW_DATA:created_at) as last_event
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:repo:id, RAW_DATA:repo:name
HAVING COUNT(*) > 0
ORDER BY total_events DESC
LIMIT 100;