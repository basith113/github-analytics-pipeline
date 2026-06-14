{{ config(
    materialized='view',
    schema='STAGING',
    tags=['staging', 'event-types'],
    meta={
        'owner': 'Data Engineering',
        'description': 'Parsed GitHub event type enumeration'
    }
) }}

-- Staging: Extract unique event types with metadata
-- Source: stg_github_events
-- Grain: One row per event type
-- Purpose: Foundation for dim_event_type dimension table

WITH event_type_counts AS (
  SELECT 
    event_type,
    COUNT(*) as event_count,
    COUNT(DISTINCT actor_id) as unique_actors,
    COUNT(DISTINCT repo_id) as unique_repos,
    MIN(created_at) as first_occurrence,
    MAX(created_at) as last_occurrence
  FROM {{ ref('stg_github_events') }}
  WHERE event_type IS NOT NULL
  GROUP BY event_type
)

SELECT 
  event_type,
  event_count,
  unique_actors,
  unique_repos,
  first_occurrence,
  last_occurrence,
  ROUND(event_count * 100.0 / SUM(event_count) OVER (), 2) as percent_of_total_events,
  CASE 
    WHEN event_type = 'PushEvent' THEN 'Code push to repository'
    WHEN event_type = 'PullRequestEvent' THEN 'Pull request opened/closed/reopened'
    WHEN event_type = 'IssuesEvent' THEN 'Issue opened/closed/reopened'
    WHEN event_type = 'IssueCommentEvent' THEN 'Comment added to issue/PR'
    WHEN event_type = 'WatchEvent' THEN 'User starred repository'
    WHEN event_type = 'ForkEvent' THEN 'Repository forked'
    WHEN event_type = 'CreateEvent' THEN 'Branch or tag created'
    WHEN event_type = 'DeleteEvent' THEN 'Branch or tag deleted'
    WHEN event_type = 'MemberEvent' THEN 'Collaborator added'
    WHEN event_type = 'ReleaseEvent' THEN 'Release published'
    WHEN event_type = 'PullRequestReviewEvent' THEN 'PR review submitted'
    ELSE 'Other event type'
  END as event_description,
  CURRENT_TIMESTAMP() as dbt_loaded_at
FROM event_type_counts
ORDER BY event_count DESC
