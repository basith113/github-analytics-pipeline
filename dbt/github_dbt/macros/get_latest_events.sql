{#
  Macro: get_latest_events
  
  Description:
    Returns events from the past N days with optional event type filter
    
  Arguments:
    days (integer): Number of days to look back (default: 7)
    event_type (string, optional): Filter by event type (e.g., 'PushEvent')
    limit (integer, optional): Max rows to return
#}

{% macro get_latest_events(days=7, event_type=none, limit=100000) %}
  SELECT 
    RAW_DATA:id::VARCHAR as event_id,
    RAW_DATA:type::VARCHAR as event_type,
    RAW_DATA:created_at::TIMESTAMP_NTZ as created_at,
    RAW_DATA:actor as actor,
    RAW_DATA:repo as repo,
    RAW_DATA as raw_data
  FROM {{ source('github_archive', 'github_events') }}
  WHERE DATE(RAW_DATA:created_at) >= CURRENT_DATE - {{ days }}
    {% if event_type %} AND RAW_DATA:type = '{{ event_type }}' {% endif %}
  LIMIT {{ limit }}
{% endmacro %}
