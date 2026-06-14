{{ config(
    materialized='view',
    schema='STAGING',
    tags=['staging', 'events'],
    meta={
        'owner': 'Data Engineering',
        'description': 'Parsed GitHub actor/user data'
    }
) }}

-- Staging: Extract actor dimensions into denormalized view
-- Source: stg_github_events
-- Grain: One row per unique actor
-- Purpose: Foundation for dim_actor dimension table

WITH unique_actors AS (
  SELECT DISTINCT
    actor_id,
    actor_login,
    actor_type,
    FIRST_VALUE(created_at) OVER (
      PARTITION BY actor_id 
      ORDER BY created_at
    ) as first_seen_at,
    MAX(created_at) OVER (
      PARTITION BY actor_id
    ) as last_seen_at
  FROM {{ ref('stg_github_events') }}
  WHERE actor_id IS NOT NULL
    AND actor_login IS NOT NULL
)

SELECT 
  actor_id,
  actor_login,
  actor_type,
  first_seen_at,
  last_seen_at,
  DATEDIFF(day, first_seen_at, last_seen_at) as days_active,
  CURRENT_TIMESTAMP() as dbt_loaded_at
FROM unique_actors
ORDER BY actor_id
