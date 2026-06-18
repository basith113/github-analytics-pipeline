{{ config(
    materialized='view',
    schema='STAGING',
    tags=['staging', 'repositories'],
    meta={
        'owner': 'Data Engineering',
        'description': 'Parsed GitHub repository data'
    }
) }}

-- Staging: Extract repository data into denormalized view
-- Source: stg_github_events
-- Grain: One row per unique repository
-- Purpose: Foundation for dim_repository dimension table

WITH repo_events AS (
  SELECT
    repo_id,
    repo_name,
    created_at
  FROM {{ ref('stg_github_events') }}
  WHERE repo_id IS NOT NULL
    AND repo_name IS NOT NULL
),

repo_rollup AS (
  SELECT
    repo_id,
    MIN(created_at) AS first_event_at,
    MAX(created_at) AS last_event_at
  FROM repo_events
  GROUP BY repo_id
),

latest_repo AS (
  SELECT
    repo_id,
    repo_name
  FROM repo_events
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY repo_id
    ORDER BY created_at DESC, repo_name
  ) = 1
)

SELECT 
  repo_rollup.repo_id,
  latest_repo.repo_name,
  SPLIT_PART(latest_repo.repo_name, '/', 1) as repo_owner,
  SPLIT_PART(latest_repo.repo_name, '/', 2) as repo_short_name,
  repo_rollup.first_event_at,
  repo_rollup.last_event_at,
  DATEDIFF(day, repo_rollup.first_event_at, repo_rollup.last_event_at) as days_active,
  CURRENT_TIMESTAMP() as dbt_loaded_at
FROM repo_rollup
INNER JOIN latest_repo
  ON repo_rollup.repo_id = latest_repo.repo_id
ORDER BY repo_rollup.repo_id
