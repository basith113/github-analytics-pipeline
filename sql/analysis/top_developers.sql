-- Top Developers Analysis
-- Identifies most active developers in raw event data

USE DATABASE GITHUB_DBT;

SELECT 
  RAW_DATA:actor:id as actor_id,
  RAW_DATA:actor:login as actor_login,
  RAW_DATA:actor:type as actor_type,
  COUNT(*) as total_events,
  COUNT(DISTINCT RAW_DATA:repo:id) as repositories_contributed_to,
  COUNT(DISTINCT RAW_DATA:type) as event_types,
  MIN(RAW_DATA:created_at) as first_event,
  MAX(RAW_DATA:created_at) as last_event
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:actor:id, RAW_DATA:actor:login, RAW_DATA:actor:type
HAVING COUNT(*) > 0
ORDER BY total_events DESC
LIMIT 100;