-- Custom test: Verify fact table grain (one row per event)
-- Fail if duplicate event_ids exist in fact_events

SELECT COUNT(*) as duplicate_count
FROM {{ ref('fact_events') }}
GROUP BY event_id
HAVING COUNT(*) > 1