-- Custom test: Verify SCD Type 2 logic in dim_actor
-- Each actor should have only one current record (dbt_is_current = true)

SELECT actor_id, COUNT(*) as current_count
FROM {{ ref('dim_actor') }}
WHERE dbt_is_current = true
GROUP BY actor_id
HAVING COUNT(*) > 1