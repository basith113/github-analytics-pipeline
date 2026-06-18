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

WITH actor_events AS (
  SELECT
    actor_id,
    actor_login,
    CASE
      WHEN actor_type IS NOT NULL THEN actor_type
      WHEN actor_login ILIKE '%[bot]' OR actor_login ILIKE '%bot%' THEN 'Bot'
      ELSE 'User'
    END AS actor_type,
    created_at
  FROM {{ ref('stg_github_events') }}
  WHERE actor_id IS NOT NULL
    AND actor_login IS NOT NULL
),

actor_rollup AS (
  SELECT
    actor_id,
    MIN(created_at) AS first_seen_at,
    MAX(created_at) AS last_seen_at
  FROM actor_events
  GROUP BY actor_id
),

latest_actor AS (
  SELECT
    actor_id,
    actor_login,
    actor_type
  FROM actor_events
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY actor_id
    ORDER BY created_at DESC, actor_login
  ) = 1
)

SELECT 
  actor_rollup.actor_id,
  latest_actor.actor_login,
  latest_actor.actor_type,
  actor_rollup.first_seen_at,
  actor_rollup.last_seen_at,
  DATEDIFF(day, actor_rollup.first_seen_at, actor_rollup.last_seen_at) as days_active,
  CURRENT_TIMESTAMP() as dbt_loaded_at
FROM actor_rollup
INNER JOIN latest_actor
  ON actor_rollup.actor_id = latest_actor.actor_id
ORDER BY actor_rollup.actor_id
