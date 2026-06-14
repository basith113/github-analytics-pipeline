-- Event Type Distribution Analysis
-- Shows breakdown of GitHub event types in raw data

USE DATABASE GITHUB_DBT;

SELECT 
  RAW_DATA:type as event_type,
  COUNT(*) as event_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percent_of_total,
  COUNT(DISTINCT RAW_DATA:actor:id) as unique_actors,
  COUNT(DISTINCT RAW_DATA:repo:id) as unique_repos,
  MIN(RAW_DATA:created_at) as first_occurrence,
  MAX(RAW_DATA:created_at) as last_occurrence
FROM RAW.GITHUB_EVENTS
GROUP BY RAW_DATA:type
ORDER BY event_count DESC;