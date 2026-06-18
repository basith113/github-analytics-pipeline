-- Custom test: Verify staging data is recent
-- Alert if most recent event is older than expected

WITH freshness AS (
  SELECT
    MAX(created_at) AS latest_event,
    CURRENT_TIMESTAMP() AS check_time,
    DATEDIFF('hour', MAX(created_at), CURRENT_TIMESTAMP()) AS hours_behind
  FROM {{ ref('stg_github_events') }}
)

SELECT *
FROM freshness
WHERE hours_behind > 2
