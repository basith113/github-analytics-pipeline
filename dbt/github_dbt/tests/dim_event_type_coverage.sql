-- Custom test: Verify all event types in staging are covered in dimension
-- Fail if fact table references event types not in dim_event_type

SELECT DISTINCT f.event_type
FROM {{ ref('fact_events') }} f
LEFT JOIN {{ ref('dim_event_type') }} d ON f.event_type = d.event_type
WHERE d.event_type IS NULL
  AND f.event_type IS NOT NULL