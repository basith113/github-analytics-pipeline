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

WITH unique_repos AS (
  SELECT DISTINCT
    repo_id,
    repo_name,
    FIRST_VALUE(created_at) OVER (
      PARTITION BY repo_id 
      ORDER BY created_at
    ) as first_event_at,
    MAX(created_at) OVER (
      PARTITION BY repo_id
    ) as last_event_at
  FROM {{ ref('stg_github_events') }}
  WHERE repo_id IS NOT NULL
    AND repo_name IS NOT NULL
)

SELECT 
  repo_id,
  repo_name,
  SPLIT_PART(repo_name, '/', 1) as repo_owner,
  SPLIT_PART(repo_name, '/', 2) as repo_short_name,
  first_event_at,
  last_event_at,
  DATEDIFF(day, first_event_at, last_event_at) as days_active,
  CURRENT_TIMESTAMP() as dbt_loaded_at
FROM unique_repos
ORDER BY repo_id
