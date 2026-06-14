"""
test_ingestion_setup.py - Test ingestion utilities

Validates:
  - GH Archive client can connect and download
  - Snowflake connection works
  - Utilities are functional

Run this before starting Phase 4 backfill.

Usage:
    python test_ingestion_setup.py
"""

import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ingestion.utils.helpers import (
    get_logger,
    load_config,
    get_last_n_days,
    get_date_hour_string,
    get_latest_available_file_name,
)
from ingestion.utils.gharchive_client import GHArchiveClient
from ingestion.utils.snowflake_loader import SnowflakeConnection

logger = get_logger(__name__)


def test_configuration():
    """Test that configuration loads successfully."""
    logger.info("=" * 60)
    logger.info("TEST 1: Configuration Loading")
    logger.info("=" * 60)
    
    try:
        config = load_config("configs/config.yaml")
        logger.info(f"✓ Configuration loaded successfully")
        logger.info(f"  - GH Archive base URL: {config['gharchive']['base_url']}")
        logger.info(f"  - Snowflake batch size: {config['snowflake']['chunk_size']}")
        return True
    except Exception as e:
        logger.error(f"✗ Configuration loading failed: {e}")
        return False


def test_helpers():
    """Test utility functions."""
    logger.info("=" * 60)
    logger.info("TEST 2: Helper Utilities")
    logger.info("=" * 60)
    
    try:
        # Test date utilities
        dates = get_last_n_days(3)
        logger.info(f"✓ get_last_n_days(3) returned {len(dates)} dates")
        
        date_str = get_date_hour_string(dates[0], 5)
        logger.info(f"✓ get_date_hour_string() produced: {date_str}")
        
        latest = get_latest_available_file_name()
        logger.info(f"✓ Latest available file: {latest}")
        
        return True
    except Exception as e:
        logger.error(f"✗ Helper utilities test failed: {e}")
        return False


def test_gh_archive_connection():
    """Test GH Archive client can connect."""
    logger.info("=" * 60)
    logger.info("TEST 3: GH Archive Connection")
    logger.info("=" * 60)
    
    try:
        client = GHArchiveClient()
        logger.info(f"✓ GH Archive client created")
        
        # Check if a recent file exists
        test_date = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        test_date -= timedelta(days=1)
        
        url = client.build_file_url(test_date, 0)
        logger.info(f"✓ Built URL: {url}")
        
        # Try to check if file exists
        exists = client.file_exists(test_date, 0)
        logger.info(f"✓ File existence check: {exists}")
        
        client.close()
        logger.info(f"✓ Client closed successfully")
        return True
    except Exception as e:
        logger.error(f"✗ GH Archive connection test failed: {e}")
        return False


def test_snowflake_connection():
    """Test Snowflake database connection."""
    logger.info("=" * 60)
    logger.info("TEST 4: Snowflake Connection")
    logger.info("=" * 60)
    
    try:
        conn = SnowflakeConnection()
        logger.info(f"✓ Connected to Snowflake")
        logger.info(f"  - Account: {conn.account}")
        logger.info(f"  - Database: {conn.database}")
        logger.info(f"  - Schema: {conn.schema}")
        
        # Execute simple query
        cursor = conn.cursor()
        cursor.execute("SELECT CURRENT_USER() AS user")
        result = cursor.fetchone()
        logger.info(f"✓ Query executed, current user: {result[0]}")
        cursor.close()
        
        # Check if tables exist
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES "
            "WHERE TABLE_SCHEMA = 'RAW' AND TABLE_NAME = 'GITHUB_EVENTS'"
        )
        table_exists = cursor.fetchone()[0] > 0
        logger.info(f"✓ RAW.GITHUB_EVENTS table exists: {table_exists}")
        cursor.close()
        
        conn.close()
        logger.info(f"✓ Connection closed")
        return True
    except Exception as e:
        logger.error(f"✗ Snowflake connection test failed: {e}")
        return False


def test_snowflake_loader():
    """Test Snowflake loader utility."""
    logger.info("=" * 60)
    logger.info("TEST 5: Snowflake Loader")
    logger.info("=" * 60)
    
    try:
        from ingestion.utils.snowflake_loader import SnowflakeLoader
        
        loader = SnowflakeLoader()
        logger.info(f"✓ Loader created with batch size: {loader.batch_size}")
        
        # Check if file already loaded
        result = loader.file_already_loaded("2024-01-01-0.json.gz")
        logger.info(f"✓ file_already_loaded() works: False expected, got {not result}")
        
        # Try to get last successful load
        last_load = loader.get_last_successful_load()
        logger.info(f"✓ get_last_successful_load() works: {last_load}")
        
        loader.close()
        logger.info(f"✓ Loader closed")
        return True
    except Exception as e:
        logger.error(f"✗ Snowflake loader test failed: {e}")
        return False


def main():
    """Run all tests."""
    logger.info("")
    logger.info("╔" + "=" * 58 + "╗")
    logger.info("║  GitHub Analytics Pipeline - Ingestion Setup Tests      ║")
    logger.info("╚" + "=" * 58 + "╝")
    logger.info("")
    
    tests = [
        ("Configuration", test_configuration),
        ("Helpers", test_helpers),
        ("GH Archive Connection", test_gh_archive_connection),
        ("Snowflake Connection", test_snowflake_connection),
        ("Snowflake Loader", test_snowflake_loader),
    ]
    
    results = {}
    for test_name, test_func in tests:
        try:
            results[test_name] = test_func()
        except Exception as e:
            logger.error(f"Test '{test_name}' crashed: {e}")
            results[test_name] = False
        logger.info("")
    
    # Summary
    logger.info("=" * 60)
    logger.info("TEST SUMMARY")
    logger.info("=" * 60)
    
    for test_name, passed in results.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        logger.info(f"{status}: {test_name}")
    
    passed_count = sum(results.values())
    total_count = len(results)
    logger.info(f"\nTotal: {passed_count}/{total_count} tests passed")
    
    if passed_count == total_count:
        logger.info("")
        logger.info("🎉 All tests passed! Ready for Phase 4 - Backfill")
        return 0
    else:
        logger.error("")
        logger.error("❌ Some tests failed. Review errors above.")
        return 1


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
