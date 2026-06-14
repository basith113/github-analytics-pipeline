{#
  Macro: parse_github_event
  
  Description:
    Extracts key fields from raw GitHub event JSON
    Handles null/missing fields gracefully
#}

{% macro parse_github_event() %}
  RAW_DATA:id::VARCHAR as event_id,
  RAW_DATA:type::VARCHAR as event_type,
  RAW_DATA:actor:id::INTEGER as actor_id,
  RAW_DATA:actor:login::VARCHAR as actor_login,
  RAW_DATA:actor:type::VARCHAR as actor_type,
  RAW_DATA:repo:id::INTEGER as repo_id,
  RAW_DATA:repo:name::VARCHAR as repo_name,
  RAW_DATA:created_at::TIMESTAMP_NTZ as created_at,
  RAW_DATA:payload as payload,
  FILE_NAME as source_file,
  LOAD_TS as loaded_at
{% endmacro %}
