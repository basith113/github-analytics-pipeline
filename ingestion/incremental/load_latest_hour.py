"""
load_latest_hour.py - Incremental loading of latest GH Archive file

This script:
  1. Determines the latest available GH Archive file
  2. Checks if it's already been loaded
  3. Downloads the file if new
  4. Loads events into Snowflake
  5. Records in LOAD_HISTORY
  6. Suitable for hourly scheduling (cron or Task Scheduler)

Usage:
    python ingestion/incremental/load_latest_hour.py

Schedule:
    - Run every hour at :05 past the hour (e.g., 10:05, 11:05, etc.)
    - GH Archive files are created at :00 UTC

Expected Runtime: 5-15 seconds
Expected Rows: ~10K per hour

Exit Codes:
    0: Success (new file loaded or already loaded)
    1: Error (requires investigation)
"""

import sys
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Tuple

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ingestion.utils.helpers import (
    get_logger,
    get_latest_available_file_name,
    parse_date_hour_string,
    get_file_hour_timestamp,
    Timer,
)
from ingestion.utils.gharchive_client import GHArchiveClient
from ingestion.utils.snowflake_loader import SnowflakeLoader

logger = get_logger(__name__)


class IncrementalLoader:
    """
    Loads the latest available GH Archive file.
    
    Designed for hourly execution:
      - Check for new files every hour
      - Skip if already loaded (idempotent)
      - Minimal latency (5-15 seconds)
      - Suitable for production scheduling
    """
    
    def __init__(self, look_back_hours: int = 2):
        """
        Initialize incremental loader.
        
        Args:
            look_back_hours: How many hours back to check for latest file
                            (handles delays in GH Archive publication)
        """
        self.look_back_hours = look_back_hours
        self.client = GHArchiveClient()
        self.loader = SnowflakeLoader()
        
        logger.info(f"Incremental loader initialized (look_back_hours={look_back_hours})")
    
    def get_latest_file_to_load(self) -> Optional[Tuple[str, datetime, int]]:
        """
        Find the latest GH Archive file that hasn't been loaded yet.
        
        Checks up to N hours back to account for delays.
        
        Returns:
            Tuple of (file_name, date, hour) or None if no new files
            
        Example:
            >>> loader = IncrementalLoader()
            >>> result = loader.get_latest_file_to_load()
            >>> if result:
            ...     file_name, date, hour = result
            ...     print(f"Found new file: {file_name}")
        """
        logger.info(f"Checking for new files (look_back_hours={self.look_back_hours})")
        
        file_name = get_latest_available_file_name()
        date, hour = parse_date_hour_string(file_name)
        
        logger.info(f"Latest available file: {file_name}")
        
        # Check if already loaded
        if self.loader.file_already_loaded(file_name):
            logger.info(f"File already loaded: {file_name}")
            return None
        
        logger.info(f"New file found: {file_name}")
        return (file_name, date, hour)
    
    def process(self) -> Tuple[bool, str, Optional[int]]:
        """
        Download and load the latest file.
        
        Returns:
            Tuple of (success, message, row_count)
            
        Example:
            >>> success, message, row_count = loader.process()
            >>> print(f"{'Success' if success else 'Skipped'}: {message}")
            >>> if row_count:
            ...     print(f"Loaded {row_count} events")
        """
        logger.info("")
        logger.info("=" * 70)
        logger.info("Incremental Load Started")
        logger.info("=" * 70)
        logger.info("")
        
        try:
            # Find new file
            result = self.get_latest_file_to_load()
            
            if result is None:
                message = "No new files to load"
                logger.info(message)
                return (True, message, None)
            
            file_name, date, hour = result
            file_hour = get_file_hour_timestamp(file_name)
            
            # Download
            logger.info(f"↓ Downloading: {file_name}")
            with Timer(f"Download {file_name}", logger):
                events = self.client.download_events(date, hour, validate=True)
            
            if not events:
                message = f"No events in file: {file_name}"
                logger.warning(message)
                # Still record as success (file loaded but was empty)
                self.loader.record_load_success(
                    file_name,
                    file_hour,
                    0,
                    0
                )
                return (True, message, 0)
            
            # Load
            logger.info(f"↑ Loading {len(events)} events from {file_name}")
            with Timer(f"Load {file_name}", logger):
                row_count = self.loader.load_events(events, file_name)
            
            # Record success
            self.loader.record_load_success(
                file_name,
                file_hour,
                row_count,
                0  # Duration not tracked in this simplified version
            )
            
            message = f"✓ Loaded {row_count} events from {file_name}"
            logger.info(message)
            
            return (True, message, row_count)
        
        except Exception as e:
            error_msg = str(e)
            logger.error(f"✗ Load failed: {error_msg}", exc_info=True)
            
            # Optionally record failure
            try:
                file_name = get_latest_available_file_name()
                date, hour = parse_date_hour_string(file_name)
                file_hour = get_file_hour_timestamp(file_name)
                self.loader.record_load_failure(file_name, file_hour, error_msg)
            except Exception as record_error:
                logger.error(f"Could not record failure: {record_error}")
            
            return (False, error_msg, None)
    
    def close(self):
        """Close connections."""
        self.client.close()
        self.loader.close()
        logger.debug("Incremental loader closed")


def main():
    """Main entry point."""
    logger.info("")
    logger.info("GitHub Analytics Pipeline - Incremental Load")
    logger.info(f"Execution time: {datetime.now(timezone.utc)}")
    logger.info("")
    
    try:
        loader = IncrementalLoader()
        success, message, row_count = loader.process()
        loader.close()
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("Incremental Load Summary")
        logger.info("=" * 70)
        logger.info(f"Status: {'✓ SUCCESS' if success else '✗ FAILED'}")
        logger.info(f"Message: {message}")
        if row_count is not None:
            logger.info(f"Rows Loaded: {row_count:,}")
        logger.info("")
        
        return 0 if success else 1
    
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 2


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
