"""
load_last_7_days.py - Initial backfill of past 7 days of GitHub events

This script:
  1. Calculates dates for past 7 days
  2. Downloads all hourly files (7 days * 24 hours = 168 files)
  3. Loads events into Snowflake RAW.GITHUB_EVENTS
  4. Tracks each file in RAW.LOAD_HISTORY
  5. Validates data quality and row counts
  6. Provides detailed logging and progress tracking

Usage:
    python ingestion/backfill/load_last_7_days.py

Expected Runtime: 30-45 minutes (network dependent)

Output:
    - RAW.GITHUB_EVENTS: ~2-2.5M events
    - RAW.LOAD_HISTORY: 168 load records (one per file)
    - logs/ingestion.log: Detailed execution log
"""

import sys
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Tuple

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ingestion.utils.helpers import (
    get_logger,
    get_date_hour_string,
    get_file_hour_timestamp,
    Timer,
)
from ingestion.utils.gharchive_client import GHArchiveClient
from ingestion.utils.snowflake_loader import SnowflakeLoader

logger = get_logger(__name__)


class BackfillProcessor:
    """
    Handles backfill of historical GitHub events.
    
    Workflow:
      1. Generate list of files to load (past 7 days)
      2. For each file:
         a. Check if already loaded (skip if yes)
         b. Download from GH Archive
         c. Load into Snowflake
         d. Record in LOAD_HISTORY
    """
    
    def __init__(self, days: int = 7):
        """
        Initialize backfill processor.
        
        Args:
            days: Number of days to backfill (default: 7)
        """
        self.days = days
        self.client = GHArchiveClient()
        self.loader = SnowflakeLoader()
        
        # Statistics
        self.stats = {
            'total_files': 0,
            'files_downloaded': 0,
            'files_skipped': 0,
            'files_failed': 0,
            'total_events': 0,
            'total_rows_loaded': 0,
            'start_time': None,
            'end_time': None,
        }
        
        logger.info(f"Backfill processor initialized (days={days})")
    
    def generate_file_list(self) -> List[Tuple[datetime, int]]:
        """
        Generate list of (date, hour) tuples for the last N rolling days.
        
        Returns:
            List of (datetime, hour) tuples
            
        Example:
            >>> processor = BackfillProcessor(days=2)
            >>> files = processor.generate_file_list()
            >>> len(files)
            48  # 2 days * 24 hours
        """
        latest_hour = datetime.now(timezone.utc).replace(
            minute=0,
            second=0,
            microsecond=0,
        ) - timedelta(hours=1)
        start_hour = latest_hour - timedelta(hours=(self.days * 24) - 1)
        file_list = []

        current_hour = start_hour
        while current_hour <= latest_hour:
            file_list.append((current_hour, current_hour.hour))
            current_hour += timedelta(hours=1)
        
        logger.info(f"Generated list of {len(file_list)} files to load")
        return file_list
    
    def process_file(self, date: datetime, hour: int) -> Tuple[bool, int, str]:
        """
        Download and load a single file.
        
        Args:
            date: Date of file
            hour: Hour of file (0-23)
            
        Returns:
            Tuple of (success, row_count, message)
            
        Example:
            >>> success, rows, msg = processor.process_file(date, 3)
            >>> print(f"{rows} events loaded" if success else f"Failed: {msg}")
        """
        file_name = f"{get_date_hour_string(date, hour)}.json.gz"
        file_hour = get_file_hour_timestamp(file_name)
        
        try:
            # Check if already loaded
            if self.loader.file_already_loaded(file_name):
                logger.info(f"⊘ Skipped (already loaded): {file_name}")
                self.stats['files_skipped'] += 1
                return (True, 0, "Already loaded")
            
            # Download
            logger.info(f"↓ Downloading: {file_name}")
            events = self.client.download_events(date, hour, validate=True)
            
            if not events:
                logger.warning(f"⚠ No events in file: {file_name}")
                self.stats['files_skipped'] += 1
                return (True, 0, "No events in file")
            
            # Load
            logger.info(f"↑ Loading {len(events)} events from {file_name}")
            
            with Timer(f"Load {file_name}", logger):
                row_count = self.loader.load_events(events, file_name)
            
            # Record success
            duration_seconds = 0  # Simplified for this script
            self.loader.record_load_success(
                file_name,
                file_hour,
                row_count,
                duration_seconds
            )
            
            logger.info(f"✓ Success: {file_name} ({row_count} rows)")
            self.stats['files_downloaded'] += 1
            self.stats['total_rows_loaded'] += row_count
            
            return (True, row_count, "Success")
        
        except Exception as e:
            error_msg = str(e)[:1000]
            logger.error(f"✗ Failed: {file_name} - {error_msg}")
            
            try:
                self.loader.record_load_failure(file_name, file_hour, error_msg)
            except Exception as log_error:
                logger.error(f"Could not record failure: {log_error}")
            
            self.stats['files_failed'] += 1
            return (False, 0, error_msg)
    
    def run(self) -> bool:
        """
        Execute backfill process.
        
        Returns:
            True if completed successfully, False if critical error
        """
        logger.info("")
        logger.info("╔" + "=" * 68 + "╗")
        logger.info("║  GitHub Analytics Pipeline - 7-Day Backfill Started       ║")
        logger.info("╚" + "=" * 68 + "╝")
        logger.info("")
        
        self.stats['start_time'] = datetime.now(timezone.utc)
        
        # Generate file list
        file_list = self.generate_file_list()
        self.stats['total_files'] = len(file_list)
        
        logger.info(f"Starting backfill of {len(file_list)} files...")
        logger.info("")
        
        # Process each file
        for file_num, (date, hour) in enumerate(file_list, 1):
            progress = f"[{file_num}/{len(file_list)}]"
            logger.info(f"{progress} Processing: {get_date_hour_string(date, hour)}")
            
            try:
                success, row_count, message = self.process_file(date, hour)
            except Exception as e:
                logger.error(f"{progress} Unexpected error: {e}")
                self.stats['files_failed'] += 1
                continue
        
        self.stats['end_time'] = datetime.now(timezone.utc)
        
        # Print summary
        self.print_summary()
        
        return self.stats['files_failed'] == 0
    
    def print_summary(self):
        """Print execution summary and statistics."""
        logger.info("")
        logger.info("╔" + "=" * 68 + "╗")
        logger.info("║  Backfill Summary                                          ║")
        logger.info("╚" + "=" * 68 + "╝")
        logger.info("")
        
        # Time calculation
        duration = self.stats['end_time'] - self.stats['start_time']
        duration_seconds = duration.total_seconds()
        
        logger.info(f"Total Files:           {self.stats['total_files']:>8}")
        logger.info(f"Files Downloaded:      {self.stats['files_downloaded']:>8}")
        logger.info(f"Files Skipped:         {self.stats['files_skipped']:>8}")
        logger.info(f"Files Failed:          {self.stats['files_failed']:>8}")
        logger.info("")
        logger.info(f"Total Events Loaded:   {self.stats['total_rows_loaded']:>8:,}")
        logger.info("")
        logger.info(f"Duration:              {int(duration_seconds):>8}s ({duration_seconds/60:.1f}m)")
        logger.info(f"Avg per file:          {duration_seconds/max(self.stats['files_downloaded'], 1):>8.1f}s")
        logger.info("")
        
        # Status
        if self.stats['files_failed'] == 0:
            logger.info("Status:                ✓ SUCCESS")
        else:
            logger.error(f"Status:                ✗ {self.stats['files_failed']} files failed")
        
        logger.info("")
    
    def close(self):
        """Close connections."""
        self.client.close()
        self.loader.close()
        logger.info("Backfill processor closed")


def validate_backfill() -> bool:
    """
    Validate backfill completion by checking Snowflake.
    
    Returns:
        True if validation passes
    """
    logger.info("")
    logger.info("=" * 70)
    logger.info("Validating Backfill Results")
    logger.info("=" * 70)
    logger.info("")
    
    try:
        loader = SnowflakeLoader()
        cursor = loader.connection.cursor()
        
        # Check row counts
        cursor.execute("SELECT COUNT(*) FROM RAW.GITHUB_EVENTS")
        event_count = cursor.fetchone()[0]
        logger.info(f"Total events in RAW.GITHUB_EVENTS: {event_count:,}")
        
        # Check load history
        cursor.execute("SELECT COUNT(*) FROM RAW.LOAD_HISTORY WHERE STATUS = 'SUCCESS'")
        load_count = cursor.fetchone()[0]
        logger.info(f"Successful loads in LOAD_HISTORY: {load_count}")
        
        # Check load failures
        cursor.execute("SELECT COUNT(*) FROM RAW.LOAD_HISTORY WHERE STATUS = 'FAILED'")
        failure_count = cursor.fetchone()[0]
        logger.info(f"Failed loads in LOAD_HISTORY: {failure_count}")
        
        # Date range
        cursor.execute(
            "SELECT MIN(RAW_DATA:created_at), MAX(RAW_DATA:created_at) FROM RAW.GITHUB_EVENTS"
        )
        result = cursor.fetchone()
        if result[0]:
            logger.info(f"Date range: {result[0]} to {result[1]}")
        
        # Validation result
        logger.info("")
        if event_count > 0 and load_count > 0:
            logger.info("✓ Validation PASSED - Backfill completed successfully")
            loader.close()
            return True
        else:
            logger.error("✗ Validation FAILED - No data found")
            loader.close()
            return False
    
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        return False


def main():
    """Main entry point."""
    try:
        # Create processor
        processor = BackfillProcessor(days=7)
        
        # Run backfill
        success = processor.run()
        
        # Validate
        validation_passed = validate_backfill()
        
        # Cleanup
        processor.close()
        
        # Exit
        if success and validation_passed:
            logger.info("")
            logger.info("🎉 Backfill completed successfully!")
            logger.info("📊 Proceed to Phase 5: Incremental Hourly Loading")
            return 0
        else:
            logger.error("")
            logger.error("❌ Backfill failed - Review errors above")
            return 1
    
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 2


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
