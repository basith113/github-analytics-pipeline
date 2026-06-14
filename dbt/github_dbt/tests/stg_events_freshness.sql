-- Custom test: Verify staging data is recent
-- Alert if most recent event is older than expected

SELECT 
  MAX(created_at) as latest_event,
  CURRENT_TIMESTAMP() as check_time,
  DATEDIFF('hour', MAX(created_at), CURRENT_TIMESTAMP()) as hours_behind
FROM {{ ref('stg_github_events') }}
WHERE DATEDIFF('hour', MAX(created_at), CURRENT_TIMESTAMP()) > 2