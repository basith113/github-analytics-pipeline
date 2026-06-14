"""
helpers.py - Utility functions for GitHub Analytics Pipeline

Contains:
  - Logging configuration and setup
  - Date/time utilities
  - Configuration management
  - Error handling and retries
  - Common utility functions
"""

import logging
import logging.config
import os
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Dict, Optional, TypeVar
import yaml
from functools import wraps
import time

# Type variable for retry decorator
F = TypeVar('F', bound=Callable[..., Any])

# ============================================================
# Configuration Management
# ============================================================

def load_config(config_path: str = "configs/config.yaml") -> Dict[str, Any]:
    """
    Load configuration from YAML file.
    
    Args:
        config_path: Path to config.yaml file
        
    Returns:
        Dictionary containing configuration
        
    Raises:
        FileNotFoundError: If config file doesn't exist
        yaml.YAMLError: If YAML is malformed
    """
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")
    
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    return config


def load_logging_config(config_path: str = "configs/logging.yaml") -> None:
    """
    Load logging configuration from YAML file.
    
    Args:
        config_path: Path to logging.yaml file
    """
    if not os.path.exists(config_path):
        # Fall back to basic logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return
    
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Create logs directory if it doesn't exist
    os.makedirs('logs', exist_ok=True)
    
    logging.config.dictConfig(config)


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance with the given name.
    
    Args:
        name: Logger name (typically __name__)
        
    Returns:
        Configured logger instance
    """
    return logging.getLogger(name)


# ============================================================
# Date/Time Utilities
# ============================================================

def get_utc_now() -> datetime:
    """Get current UTC time as timezone-aware datetime."""
    return datetime.now(timezone.utc)


def get_last_n_days(days: int = 7) -> list[datetime]:
    """
    Get list of dates for the past N days.
    
    Args:
        days: Number of days to include
        
    Returns:
        List of datetime objects for each day (midnight UTC)
        
    Example:
        >>> dates = get_last_n_days(3)
        >>> [d.strftime('%Y-%m-%d') for d in dates]
        ['2024-01-12', '2024-01-13', '2024-01-14']
    """
    now = get_utc_now().replace(hour=0, minute=0, second=0, microsecond=0)
    dates = []
    for i in range(days):
        date = now - timedelta(days=i)
        dates.append(date)
    return sorted(dates)  # Return in chronological order


def get_date_hour_string(date: datetime, hour: int) -> str:
    """
    Convert date and hour to GH Archive filename format.
    
    Args:
        date: datetime object
        hour: Hour (0-23)
        
    Returns:
        String in format: YYYY-MM-DD-H
        
    Example:
        >>> from datetime import datetime
        >>> d = datetime(2024, 1, 15)
        >>> get_date_hour_string(d, 3)
        '2024-01-15-3'
    """
    return f"{date.strftime('%Y-%m-%d')}-{hour}"


def parse_date_hour_string(date_hour_str: str) -> tuple[datetime, int]:
    """
    Parse GH Archive filename format to date and hour.
    
    Args:
        date_hour_str: String in format: YYYY-MM-DD-H
        
    Returns:
        Tuple of (datetime, hour)
        
    Example:
        >>> d, h = parse_date_hour_string('2024-01-15-3')
        >>> d.strftime('%Y-%m-%d'), h
        ('2024-01-15', 3)
    """
    parts = date_hour_str.rsplit('-', 1)
    date = datetime.strptime(parts[0], '%Y-%m-%d').replace(tzinfo=timezone.utc)
    hour = int(parts[1])
    return date, hour


def get_latest_available_file_name() -> str:
    """
    Get the filename for the latest available GH Archive file.
    
    GH Archive files are created hourly at the top of the hour,
    so we look back up to 2 hours to handle potential delays.
    
    Returns:
        File name in format: YYYY-MM-DD-H
        
    Example:
        >>> get_latest_available_file_name()
        '2024-01-15-9'  # If current time is 2024-01-15 10:30 UTC
    """
    now = get_utc_now()
    
    # Try last 2 hours to account for delays in GH Archive
    for hours_back in range(1, 3):
        file_time = now - timedelta(hours=hours_back)
        file_time = file_time.replace(minute=0, second=0, microsecond=0)
        return get_date_hour_string(file_time, file_time.hour)


def get_file_hour_timestamp(file_name: str) -> datetime:
    """
    Convert GH Archive filename to UTC timestamp.
    
    Args:
        file_name: File name in format: YYYY-MM-DD-H
        
    Returns:
        datetime object at the hour represented by the file
        
    Example:
        >>> get_file_hour_timestamp('2024-01-15-3')
        datetime(2024, 1, 15, 3, 0, 0, tzinfo=timezone.utc)
    """
    date, hour = parse_date_hour_string(file_name)
    return date.replace(hour=hour)


# ============================================================
# Error Handling & Retry Logic
# ============================================================

def retry(max_attempts: int = 3, delay_seconds: float = 5, backoff: float = 2.0) -> Callable:
    """
    Decorator for retrying functions with exponential backoff.
    
    Args:
        max_attempts: Maximum number of attempts
        delay_seconds: Initial delay between retries (seconds)
        backoff: Multiplier for exponential backoff
        
    Returns:
        Decorated function
        
    Example:
        @retry(max_attempts=3, delay_seconds=1)
        def download_file(url):
            # Function that might fail
            ...
    """
    def decorator(func: F) -> F:
        @wraps(func)
        def wrapper(*args, **kwargs):
            logger = get_logger(func.__module__)
            current_delay = delay_seconds
            
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        logger.error(f"Failed after {max_attempts} attempts: {e}")
                        raise
                    
                    logger.warning(
                        f"Attempt {attempt}/{max_attempts} failed: {e}. "
                        f"Retrying in {current_delay} seconds..."
                    )
                    time.sleep(current_delay)
                    current_delay *= backoff
        
        return wrapper
    return decorator


def handle_exception(logger: logging.Logger, exception: Exception, context: str = "") -> None:
    """
    Standard exception handling and logging.
    
    Args:
        logger: Logger instance
        exception: The exception that occurred
        context: Additional context string
    """
    error_msg = f"Error{' - ' + context if context else ''}: {str(exception)}"
    logger.error(error_msg, exc_info=True)


# ============================================================
# File Utilities
# ============================================================

def ensure_directory(path: str) -> Path:
    """
    Ensure directory exists, create if necessary.
    
    Args:
        path: Directory path
        
    Returns:
        Path object
    """
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def get_file_size_mb(file_path: str) -> float:
    """
    Get file size in megabytes.
    
    Args:
        file_path: Path to file
        
    Returns:
        File size in MB
    """
    return os.path.getsize(file_path) / (1024 * 1024)


# ============================================================
# JSON Utilities
# ============================================================

def is_valid_json(data: str) -> bool:
    """
    Check if string is valid JSON.
    
    Args:
        data: String to validate
        
    Returns:
        True if valid JSON, False otherwise
    """
    try:
        json.loads(data)
        return True
    except json.JSONDecodeError:
        return False


def safe_json_parse(data: str, logger: Optional[logging.Logger] = None) -> Optional[dict]:
    """
    Safely parse JSON with error handling.
    
    Args:
        data: JSON string to parse
        logger: Optional logger for error reporting
        
    Returns:
        Parsed JSON object or None if parsing fails
    """
    try:
        return json.loads(data)
    except json.JSONDecodeError as e:
        if logger:
            logger.error(f"JSON parsing error: {e}")
        return None


# ============================================================
# Data Validation
# ============================================================

def validate_json_event(event: dict) -> bool:
    """
    Validate that an event has required GH Archive fields.
    
    Args:
        event: Event dictionary from GH Archive
        
    Returns:
        True if event is valid, False otherwise
    """
    required_fields = ['id', 'type', 'actor', 'repo', 'created_at']
    return all(field in event for field in required_fields)


def sanitize_for_snowflake(value: Any) -> Any:
    """
    Sanitize values for Snowflake insertion.
    
    Args:
        value: Value to sanitize
        
    Returns:
        Sanitized value safe for Snowflake
    """
    if value is None:
        return None
    if isinstance(value, str):
        # Remove null characters
        return value.replace('\x00', '')
    return value


# ============================================================
# Performance Utilities
# ============================================================

class Timer:
    """Context manager for timing code blocks."""
    
    def __init__(self, name: str, logger: Optional[logging.Logger] = None):
        self.name = name
        self.logger = logger
        self.start_time = None
        self.elapsed = 0
    
    def __enter__(self):
        self.start_time = time.time()
        return self
    
    def __exit__(self, *args):
        self.elapsed = time.time() - self.start_time
        if self.logger:
            self.logger.info(f"{self.name} completed in {self.elapsed:.2f} seconds")


# ============================================================
# Initialization
# ============================================================

# Configure logging on module load
load_logging_config()
logger = get_logger(__name__)

logger.debug("Helpers module initialized")