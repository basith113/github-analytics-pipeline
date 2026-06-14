-- Custom test: Verify fact table has all foreign keys populated
-- All fact records must reference valid dimensions

SELECT COUNT(*) as missing_actor_key
FROM {{ ref('fact_events') }}
WHERE actor_key IS NULL
  AND event_key IS NOT NULL

UNION ALL

SELECT COUNT(*) as missing_repo_key
FROM {{ ref('fact_events') }}
WHERE repo_key IS NULL
  AND event_key IS NOT NULL

UNION ALL

SELECT COUNT(*) as missing_event_type_key
FROM {{ ref('fact_events') }}
WHERE event_type_key IS NULL
  AND event_key IS NOT NULL