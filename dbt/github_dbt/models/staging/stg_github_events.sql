{{ config(
    materialized='table',
    schema='STAGING',
    tags=['staging', 'daily'],
    meta={
        'owner': 'Data Engineering',
        'description': 'Staging table for GitHub events - parsed from raw JSON'
    }
) }}

-- Staging: Parse raw GitHub events into clean columns
-- Source: RAW.GITHUB_EVENTS
-- Grain: One row per event
-- Records: ~2.5M from 7-day backfill, ~10K per hour incremental

SELECT 
  {{ parse_github_event() }},
  CURRENT_TIMESTAMP() as dbt_loaded_at,
  '{{ run_started_at }}' as dbt_run_id
FROM {{ source('github_archive', 'github_events') }}
WHERE RAW_DATA:id IS NOT NULL
  AND RAW_DATA:created_at IS NOT NULL
