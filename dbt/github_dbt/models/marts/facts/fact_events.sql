{{ config(
    materialized='incremental',
    unique_key='event_id',
    on_schema_change='fail',
    incremental_strategy='merge',
    cluster_by=['event_date', 'repo_key'],
    tags=['facts', 'incremental'],
    meta={
        'owner': 'Data Engineering',
        'description': 'GitHub events fact table - incremental mode'
    }
) }}

-- Fact Table: GitHub Events (INCREMENTAL)
-- Only processes new events since last dbt run
-- Grain: One row per GitHub event
-- Strategy: MERGE (upsert) - efficient for hourly runs
-- Clustering: event_date, repo_key (common filter/join columns)

WITH github_events AS (
  SELECT 
    event_id,
    event_type,
    actor_id,
    actor_login,
    actor_type,
    repo_id,
    repo_name,
    created_at,
    source_file,
    loaded_at,
    dbt_run_id
  FROM {{ ref('stg_github_events') }}
  
  {% if execute %}
    {% if this.exists %}
      -- Incremental: Only load events newer than last run
      WHERE loaded_at > (
        SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
      )
    {% endif %}
  {% endif %}
)

SELECT 
  {{ dbt_utils.generate_surrogate_key(['event_id']) }} as event_key,
  event_id,
  {{ dbt_utils.generate_surrogate_key(['actor_id']) }} as actor_key,
  {{ dbt_utils.generate_surrogate_key(['repo_id']) }} as repo_key,
  {{ dbt_utils.generate_surrogate_key(['event_type']) }} as event_type_key,
  event_type,
  actor_id,
  actor_login,
  repo_id,
  repo_name,
  created_at,
  DATE(created_at) as event_date,
  HOUR(created_at) as event_hour,
  DAYNAME(created_at) as event_day_of_week,
  WEEK(created_at) as event_week,
  MONTH(created_at) as event_month,
  YEAR(created_at) as event_year,
  source_file,
  loaded_at,
  CURRENT_TIMESTAMP() as dbt_created_at
FROM github_events
WHERE event_id IS NOT NULL
  AND created_at IS NOT NULL
