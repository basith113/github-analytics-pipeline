"""
gharchive_client.py - GH Archive API client

Responsible for:
  - Building GH Archive URLs
  - Downloading hourly JSON files
  - Decompressing .gz files
  - Validating file integrity
  - Handling retries and failures
  - Providing file availability information
"""

import gzip
import json
import logging
from datetime import datetime, timezone
from io import BytesIO
from typing import Optional, List, Tuple
import requests

from ingestion.utils.helpers import (
    retry,
    get_logger,
    get_date_hour_string,
    validate_json_event,
    Timer,
)

logger = get_logger(__name__)


class GHArchiveClient:
    """
    Client for downloading GitHub events from GH Archive.
    
    GH Archive provides hourly JSON files containing all public GitHub events.
    
    Features:
      - Download files with automatic retries
      - Validate file integrity and structure
      - Parse compressed JSON
      - Handle missing files gracefully
    
    Example:
        >>> client = GHArchiveClient()
        >>> from datetime import datetime
        >>> date = datetime(2024, 1, 15)
        >>> events = client.download_events(date, hour=3)
        >>> print(f"Downloaded {len(events)} events")
    """
    
    # GH Archive base URL
    BASE_URL = "https://data.gharchive.org"
    
    # Timeout for HTTP requests (seconds)
    REQUEST_TIMEOUT = 30
    
    # File format (always gzipped JSON)
    FILE_FORMAT = "json.gz"
    
    def __init__(self, base_url: str = BASE_URL, timeout: int = REQUEST_TIMEOUT):
        """
        Initialize GH Archive client.
        
        Args:
            base_url: Base URL for GH Archive
            timeout: Request timeout in seconds
        """
        self.base_url = base_url
        self.timeout = timeout
        self.session = requests.Session()
        
        logger.info(f"GH Archive client initialized (base_url={base_url}, timeout={timeout}s)")
    
    def build_file_url(self, date: datetime, hour: int) -> str:
        """
        Build GH Archive file URL for a specific date and hour.
        
        GH Archive URLs follow pattern:
        https://data.gharchive.org/2024-01-15-3.json.gz
        
        Args:
            date: Date (datetime object)
            hour: Hour (0-23)
            
        Returns:
            Full URL to GH Archive file
            
        Example:
            >>> from datetime import datetime
            >>> client = GHArchiveClient()
            >>> url = client.build_file_url(datetime(2024, 1, 15), 3)
            >>> url
            'https://data.gharchive.org/2024-01-15-3.json.gz'
        """
        date_str = date.strftime('%Y-%m-%d')
        filename = f"{date_str}-{hour}.{self.FILE_FORMAT}"
        return f"{self.base_url}/{filename}"
    
    @retry(max_attempts=3, delay_seconds=5, backoff=2.0)
    def _download_file(self, url: str) -> bytes:
        """
        Download file from GH Archive with automatic retries.
        
        Args:
            url: Full URL to file
            
        Returns:
            Raw file contents (gzipped bytes)
            
        Raises:
            requests.RequestException: If download fails after retries
        """
        logger.debug(f"Downloading: {url}")
        
        response = self.session.get(url, timeout=self.timeout, stream=True)
        response.raise_for_status()  # Raise exception for 4xx/5xx status
        
        return response.content
    
    def _decompress_file(self, gzipped_data: bytes) -> str:
        """
        Decompress gzipped JSON data.
        
        Args:
            gzipped_data: Gzipped file contents
            
        Returns:
            Decompressed JSON string
            
        Raises:
            OSError: If decompression fails
            UnicodeDecodeError: If data is not valid UTF-8
        """
        try:
            with gzip.GzipFile(fileobj=BytesIO(gzipped_data)) as gz:
                return gz.read().decode('utf-8')
        except Exception as e:
            logger.error(f"Decompression failed: {e}")
            raise
    
    def _parse_json_lines(self, json_text: str) -> List[dict]:
        """
        Parse newline-delimited JSON (NDJSON) format.
        
        GH Archive files contain one JSON object per line.
        
        Args:
            json_text: Text containing NDJSON data
            
        Returns:
            List of parsed JSON objects
            
        Example:
            >>> text = '{\"id\": 1}\\n{\"id\": 2}'
            >>> client._parse_json_lines(text)
            [{'id': 1}, {'id': 2}]
        """
        events = []
        
        for line_num, line in enumerate(json_text.strip().split('\n'), 1):
            if not line.strip():
                continue  # Skip empty lines
            
            try:
                event = json.loads(line)
                events.append(event)
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse line {line_num}: {e}")
                # Continue processing other lines
        
        return events
    
    def _validate_events(self, events: List[dict]) -> Tuple[List[dict], int]:
        """
        Validate events and filter out invalid ones.
        
        Args:
            events: List of event dictionaries
            
        Returns:
            Tuple of (valid_events, invalid_count)
        """
        valid_events = []
        invalid_count = 0
        
        for event in events:
            if validate_json_event(event):
                valid_events.append(event)
            else:
                invalid_count += 1
                logger.debug(f"Invalid event structure: {event.get('id', 'UNKNOWN')}")
        
        if invalid_count > 0:
            logger.warning(f"Skipped {invalid_count} invalid events")
        
        return valid_events, invalid_count
    
    def download_events(
        self,
        date: datetime,
        hour: int,
        validate: bool = True
    ) -> List[dict]:
        """
        Download GitHub events for a specific date and hour.
        
        Complete workflow:
          1. Build URL for date/hour
          2. Download gzipped file
          3. Decompress
          4. Parse NDJSON
          5. Validate events (optional)
          6. Return list of events
        
        Args:
            date: Date of events (datetime object)
            hour: Hour of events (0-23)
            validate: Whether to validate event structure
            
        Returns:
            List of GitHub event dictionaries
            
        Raises:
            requests.RequestException: If download fails
            OSError: If decompression fails
            json.JSONDecodeError: If JSON parsing fails
            
        Example:
            >>> from datetime import datetime
            >>> client = GHArchiveClient()
            >>> events = client.download_events(datetime(2024, 1, 15), 3)
            >>> print(f"Downloaded {len(events)} events")
            Downloaded 12345 events
        """
        url = self.build_file_url(date, hour)
        file_name = f"{date.strftime('%Y-%m-%d')}-{hour}"
        
        with Timer(f"Download {file_name}", logger):
            try:
                # Download
                gzipped_data = self._download_file(url)
                logger.debug(f"Downloaded {len(gzipped_data)} bytes")
                
                # Decompress
                json_text = self._decompress_file(gzipped_data)
                logger.debug(f"Decompressed to {len(json_text)} characters")
                
                # Parse
                events = self._parse_json_lines(json_text)
                logger.info(f"Parsed {len(events)} events from {file_name}")
                
                # Validate
                if validate:
                    valid_events, invalid_count = self._validate_events(events)
                    logger.info(
                        f"Validation: {len(valid_events)} valid, {invalid_count} invalid events"
                    )
                    events = valid_events
                
                return events
            
            except requests.exceptions.HTTPError as e:
                if e.response.status_code == 404:
                    logger.warning(f"File not found (404): {file_name}")
                    return []
                raise
    
    def file_exists(self, date: datetime, hour: int) -> bool:
        """
        Check if a file exists without downloading it.
        
        Performs a HEAD request to check file availability.
        
        Args:
            date: Date to check
            hour: Hour to check
            
        Returns:
            True if file exists, False otherwise
            
        Example:
            >>> from datetime import datetime
            >>> client = GHArchiveClient()
            >>> client.file_exists(datetime(2024, 1, 15), 3)
            True
        """
        url = self.build_file_url(date, hour)
        try:
            response = self.session.head(url, timeout=self.timeout)
            return response.status_code == 200
        except requests.RequestException:
            return False
    
    def get_available_files(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> List[str]:
        """
        Get list of available files in date range.
        
        Checks each hour to see if file exists.
        
        Args:
            start_date: Start date (inclusive)
            end_date: End date (inclusive)
            
        Returns:
            List of available file names in format: YYYY-MM-DD-H
            
        Example:
            >>> from datetime import datetime
            >>> client = GHArchiveClient()
            >>> files = client.get_available_files(
            ...     datetime(2024, 1, 14),
            ...     datetime(2024, 1, 15)
            ... )
            >>> len(files)
            48  # 2 days * 24 hours
        """
        available_files = []
        
        current = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
        end = end_date.replace(hour=23, minute=59, second=59, microsecond=0)
        
        while current <= end:
            if self.file_exists(current, current.hour):
                file_name = get_date_hour_string(current, current.hour)
                available_files.append(file_name)
            
            # Move to next hour
            from datetime import timedelta
            current += timedelta(hours=1)
        
        return available_files
    
    def close(self):
        """Close HTTP session."""
        self.session.close()
        logger.debug("GH Archive client session closed")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, *args):
        """Context manager exit."""
        self.close()


# ============================================================
# Convenience Functions
# ============================================================

def download_latest_hour_events(client: Optional[GHArchiveClient] = None) -> List[dict]:
    """
    Download GitHub events from the latest available hour.
    
    Args:
        client: Optional GHArchiveClient instance (creates new if not provided)
        
    Returns:
        List of events from latest hour
        
    Example:
        >>> events = download_latest_hour_events()
        >>> len(events)
        12000  # Approximate number of events per hour
    """
    if client is None:
        client = GHArchiveClient()
    
    from ingestion.utils.helpers import get_latest_available_file_name, parse_date_hour_string
    
    file_name = get_latest_available_file_name()
    date, hour = parse_date_hour_string(file_name)
    
    logger.info(f"Downloading latest available file: {file_name}")
    return client.download_events(date, hour)