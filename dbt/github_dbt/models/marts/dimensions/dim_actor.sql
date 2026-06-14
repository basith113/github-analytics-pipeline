{{ config(
    materialized='incremental',
    unique_key='actor_id',
    on_schema_change='fail',
    incremental_strategy='merge',
    cluster_by=['actor_id', 'dbt_is_current'],
    tags=['dimensions', 'incremental', 'scd'],
    meta={
        'owner': 'Data Engineering',
        'description': 'Actor dimension with SCD Type 2 (incremental)'
    }
) }}

-- Dimension: GitHub Actors (INCREMENTAL with SCD Type 2)
-- Tracks actor attribute changes over time
-- Only processes new actors; existing are skipped
-- Merge strategy for efficient upserts

WITH actor_staging AS (
  SELECT 
    actor_id,
    actor_login,
    actor_type,
    first_seen_at,
    last_seen_at,
    days_active
  FROM {{ ref('stg_actors') }}
)

{% if execute %}
  {% if this.exists %}
    -- Incremental: Only new actors (those not in current records)
    , new_actors AS (
      SELECT 
        {{ dbt_utils.generate_surrogate_key(['actor_id']) }} as actor_key,
        actor_staging.actor_id,
        actor_staging.actor_login,
        actor_staging.actor_type,
        actor_staging.first_seen_at,
        actor_staging.last_seen_at,
        actor_staging.days_active,
        CASE 
          WHEN actor_staging.actor_type = 'Bot' THEN true 
          ELSE false 
        END as is_bot,
        CURRENT_TIMESTAMP() as dbt_valid_from,
        CAST('2099-12-31' AS TIMESTAMP_NTZ) as dbt_valid_to,
        true as dbt_is_current,
        CURRENT_TIMESTAMP() as dbt_created_at,
        CURRENT_TIMESTAMP() as dbt_updated_at
      FROM actor_staging
      WHERE actor_id NOT IN (
        SELECT DISTINCT actor_id FROM {{ this }} WHERE dbt_is_current = true
      )
    )
    
    SELECT * FROM new_actors
    
    UNION ALL
    
    SELECT * FROM {{ this }} WHERE dbt_is_current = true
  {% else %}
    -- Full load: All actors on first run
    SELECT 
      {{ dbt_utils.generate_surrogate_key(['actor_id']) }} as actor_key,
      actor_id,
      actor_login,
      actor_type,
      first_seen_at,
      last_seen_at,
      days_active,
      CASE 
        WHEN actor_type = 'Bot' THEN true 
        ELSE false 
      END as is_bot,
      CURRENT_TIMESTAMP() as dbt_valid_from,
      CAST('2099-12-31' AS TIMESTAMP_NTZ) as dbt_valid_to,
      true as dbt_is_current,
      CURRENT_TIMESTAMP() as dbt_created_at,
      CURRENT_TIMESTAMP() as dbt_updated_at
    FROM actor_staging
    WHERE actor_id IS NOT NULL
      AND actor_login IS NOT NULL
  {% endif %}
{% else %}
  -- Parse phase: Generate schema
  SELECT 
    {{ dbt_utils.generate_surrogate_key(['actor_id']) }} as actor_key,
    actor_id,
    actor_login,
    actor_type,
    first_seen_at,
    last_seen_at,
    days_active,
    cast(false as boolean) as is_bot,
    CURRENT_TIMESTAMP() as dbt_valid_from,
    CAST('2099-12-31' AS TIMESTAMP_NTZ) as dbt_valid_to,
    true as dbt_is_current,
    CURRENT_TIMESTAMP() as dbt_created_at,
    CURRENT_TIMESTAMP() as dbt_updated_at
  FROM actor_staging
  WHERE 1=0
{% endif %}
