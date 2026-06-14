"""
Ingestion module for GitHub Analytics Pipeline

Handles downloading and loading GitHub events from GH Archive.

Submodules:
  - gharchive_client: Download events from GH Archive
  - snowflake_loader: Load events into Snowflake
  - helpers: Utility functions and logging
"""

__version__ = "1.0.0"
