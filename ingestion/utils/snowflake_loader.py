"""
snowflake_loader.py - Snowflake connection and data loading

Responsible for:
  - Establishing connections to Snowflake
  - Loading JSON events into RAW.GITHUB_EVENTS
  - Tracking loaded files in RAW.LOAD_HISTORY
  - Batch processing for performance
  - Error handling and transaction management
"""

import json
import logging
import gzip
from datetime import datetime, timezone
from typing import List, Optional, Tuple
import os
import tempfile
import uuid
from dotenv import load_dotenv
import snowflake.connector
from snowflake.connector import DictCursor

from ingestion.utils.helpers import (
    get_logger,
    Timer,
    sanitize_for_snowflake,
)

logger = get_logger(__name__)

# Load environment variables
load_dotenv()


class SnowflakeConnection:
    """
    Manages Snowflake database connections.
    
    Handles:
      - Connection pooling and lifecycle
      - Query execution
      - Transaction management
      - Error handling
    
    Example:
        >>> conn = SnowflakeConnection()
        >>> cursor = conn.cursor()
        >>> cursor.execute("SELECT * FROM TABLE LIMIT 1")
        >>> results = cursor.fetchall()
    """
    
    def __init__(
        self,
        user: Optional[str] = None,
        password: Optional[str] = None,
        account: Optional[str] = None,
        warehouse: Optional[str] = None,
        database: Optional[str] = None,
        schema: Optional[str] = None,
        role: Optional[str] = None,
    ):
        """
        Initialize Snowflake connection with credentials.
        
        Reads from environment variables if not provided:
          - SNOWFLAKE_USER
          - SNOWFLAKE_PASSWORD
          - SNOWFLAKE_ACCOUNT
          - SNOWFLAKE_WAREHOUSE
          - SNOWFLAKE_DATABASE
          - SNOWFLAKE_SCHEMA
          - SNOWFLAKE_ROLE
        
        Args:
            user: Snowflake username
            password: Snowflake password
            account: Snowflake account identifier
            warehouse: Warehouse name
            database: Database name
            schema: Schema name
            role: Role name
        """
        self.user = user or os.getenv('SNOWFLAKE_USER')
        self.password = password or os.getenv('SNOWFLAKE_PASSWORD')
        self.account = account or os.getenv('SNOWFLAKE_ACCOUNT')
        self.warehouse = warehouse or os.getenv('SNOWFLAKE_WAREHOUSE')
        self.database = database or os.getenv('SNOWFLAKE_DATABASE')
        self.schema = schema or os.getenv('SNOWFLAKE_SCHEMA')
        self.role = role or os.getenv('SNOWFLAKE_ROLE')
        
        # Validate required parameters
        required = ['user', 'password', 'account', 'warehouse']
        missing = [param for param in required if not getattr(self, param)]
        if missing:
            raise ValueError(f"Missing required Snowflake parameters: {missing}")
        
        self.connection = None
        self._connect()
    
    def _connect(self):
        """Establish connection to Snowflake."""
        try:
            self.connection = snowflake.connector.connect(
                user=self.user,
                password=self.password,
                account=self.account,
                warehouse=self.warehouse,
                database=self.database,
                schema=self.schema,
                role=self.role,
            )
            logger.info(
                f"Connected to Snowflake: {self.account} / "
                f"{self.database}.{self.schema} / {self.warehouse}"
            )
        except Exception as e:
            logger.error(f"Snowflake connection failed: {e}")
            raise
    
    def cursor(self, cursor_type=None):
        """
        Get a cursor from the connection.
        
        Args:
            cursor_type: Type of cursor (default: standard)
            
        Returns:
            Database cursor
        """
        if cursor_type == 'dict':
            return self.connection.cursor(DictCursor)
        return self.connection.cursor()
    
    def execute(self, sql: str, params: tuple = ()) -> list:
        """
        Execute a SQL query and return results.
        
        Args:
            sql: SQL statement
            params: Query parameters
            
        Returns:
            List of result rows
        """
        cursor = self.cursor()
        cursor.execute(sql, params)
        results = cursor.fetchall()
        cursor.close()
        return results
    
    def commit(self):
        """Commit current transaction."""
        self.connection.commit()
    
    def rollback(self):
        """Rollback current transaction."""
        self.connection.rollback()
    
    def close(self):
        """Close database connection."""
        if self.connection:
            self.connection.close()
            logger.debug("Snowflake connection closed")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, *args):
        """Context manager exit."""
        self.close()


class SnowflakeLoader:
    """
    Loads GitHub events into Snowflake data warehouse.
    
    Responsibilities:
      - Insert events into RAW.GITHUB_EVENTS
      - Track loads in RAW.LOAD_HISTORY
      - Check for duplicate files
      - Batch processing for performance
      - Error handling and recovery
    
    Example:
        >>> loader = SnowflakeLoader()
        >>> events = [{...}, {...}]  # List of event dicts
        >>> row_count = loader.load_events(events, "2024-01-15-3.json.gz")
        >>> print(f"Loaded {row_count} events")
    """
    
    def __init__(self, connection: Optional[SnowflakeConnection] = None, batch_size: int = 5000):
        """
        Initialize loader.
        
        Args:
            connection: Optional SnowflakeConnection instance
            batch_size: Number of records per batch insert
        """
        self.connection = connection or SnowflakeConnection()
        self.batch_size = batch_size
        logger.info(f"Snowflake loader initialized (batch_size={batch_size})")
    
    def file_already_loaded(self, file_name: str) -> bool:
        """
        Check if a file has already been loaded successfully.
        
        Args:
            file_name: File name (e.g., "2024-01-15-3.json.gz")
            
        Returns:
            True if file was loaded, False otherwise
            
        Example:
            >>> loader = SnowflakeLoader()
            >>> loader.file_already_loaded("2024-01-15-3.json.gz")
            False
        """
        cursor = self.connection.cursor()
        try:
            cursor.execute(
                "SELECT COUNT(*) FROM RAW.LOAD_HISTORY WHERE FILE_NAME = %s AND STATUS = 'SUCCESS'",
                (file_name,)
            )
            count = cursor.fetchone()[0]
            return count > 0
        finally:
            cursor.close()
    
    def get_last_successful_load(self) -> Optional[Tuple[str, datetime]]:
        """
        Get the most recently loaded file.
        
        Returns:
            Tuple of (file_name, load_timestamp) or None if no loads
        """
        cursor = self.connection.cursor()
        try:
            cursor.execute(
                "SELECT FILE_NAME, FILE_HOUR FROM RAW.LOAD_HISTORY "
                "WHERE STATUS = 'SUCCESS' ORDER BY FILE_HOUR DESC LIMIT 1"
            )
            result = cursor.fetchone()
            return result if result else None
        finally:
            cursor.close()
    
    def _insert_events_batch(
        self,
        events: List[dict],
        file_name: str,
        batch_num: int,
        total_batches: int
    ) -> int:
        """
        Insert a batch of events into GITHUB_EVENTS table.
        
        Args:
            events: List of event dictionaries
            file_name: Source file name
            batch_num: Current batch number (for logging)
            total_batches: Total number of batches (for logging)
            
        Returns:
            Number of rows inserted
        """
        cursor = self.connection.cursor()
        try:
            inserted = 0
            for event in events:
                try:
                    # Sanitize event data
                    raw_data = json.dumps(event)
                    raw_data = sanitize_for_snowflake(raw_data)
                    
                    # Insert row
                    cursor.execute(
                        "INSERT INTO RAW.GITHUB_EVENTS (RAW_DATA, FILE_NAME) SELECT PARSE_JSON(%s), %s",
                        (raw_data, file_name)
                    )
                    inserted += 1
                except Exception as e:
                    logger.warning(f"Failed to insert event {event.get('id', 'UNKNOWN')}: {e}")
                    # Continue with next event
            
            self.connection.commit()
            logger.info(
                f"Batch {batch_num}/{total_batches}: Inserted {inserted} events"
            )
            return inserted
        
        except Exception as e:
            self.connection.rollback()
            logger.error(f"Batch {batch_num} failed: {e}")
            raise
        finally:
            cursor.close()

    def _copy_events_via_stage(self, events: List[dict], file_name: str) -> int:
        """Load a full GH Archive file through a temporary Snowflake stage."""
        cursor = self.connection.cursor()
        stage_name = f"RAW.GITHUB_EVENTS_STAGE_{uuid.uuid4().hex.upper()}"
        temp_path = ""

        try:
            with tempfile.NamedTemporaryFile(
                mode="wb",
                suffix=".json.gz",
                prefix="github_events_",
                delete=False,
            ) as temp_file:
                temp_path = temp_file.name

            with gzip.open(temp_path, "wt", encoding="utf-8") as json_file:
                for event in events:
                    json_file.write(json.dumps(event, separators=(",", ":")))
                    json_file.write("\n")

            put_path = temp_path.replace("\\", "/")
            put_uri = f"file://{put_path}" if put_path.startswith("/") else f"file:///{put_path}"
            escaped_file_name = file_name.replace("'", "''")

            cursor.execute(f"CREATE TEMPORARY STAGE {stage_name} FILE_FORMAT = (TYPE = JSON)")
            cursor.execute(f"PUT '{put_uri}' @{stage_name} AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
            cursor.execute(
                f"""
                COPY INTO RAW.GITHUB_EVENTS (RAW_DATA, FILE_NAME)
                FROM (
                    SELECT $1, '{escaped_file_name}'
                    FROM @{stage_name}
                )
                FILE_FORMAT = (TYPE = JSON)
                ON_ERROR = 'ABORT_STATEMENT'
                """
            )

            copy_results = cursor.fetchall()
            rows_loaded = 0
            for row in copy_results:
                if len(row) > 3 and isinstance(row[3], int):
                    rows_loaded += row[3]

            self.connection.commit()
            logger.info("Snowflake COPY loaded %s rows from %s", rows_loaded, file_name)
            return rows_loaded
        except Exception:
            self.connection.rollback()
            raise
        finally:
            try:
                cursor.execute(f"DROP STAGE IF EXISTS {stage_name}")
            except Exception as drop_error:
                logger.warning("Could not drop temporary stage %s: %s", stage_name, drop_error)
            cursor.close()
            if temp_path and os.path.exists(temp_path):
                os.remove(temp_path)
    
    def load_events(
        self,
        events: List[dict],
        file_name: str,
        skip_if_exists: bool = True
    ) -> int:
        """
        Load GitHub events into RAW.GITHUB_EVENTS table.
        
        Features:
          - Check for duplicate files
          - Batch insert for performance
          - Error handling and partial rollback
          - Record metadata in LOAD_HISTORY
        
        Args:
            events: List of event dictionaries
            file_name: Source file name (e.g., "2024-01-15-3.json.gz")
            skip_if_exists: If True, skip if file already loaded
            
        Returns:
            Number of rows inserted
            
        Raises:
            RuntimeError: If file already loaded and skip_if_exists=False
        """
        logger.info(f"Loading {len(events)} events from {file_name}")
        
        # Check if already loaded
        if self.file_already_loaded(file_name):
            if skip_if_exists:
                logger.info(f"File already loaded (skipping): {file_name}")
                return 0
            else:
                raise RuntimeError(f"File already loaded: {file_name}")
        
        with Timer(f"Load {file_name}", logger):
            return self._copy_events_via_stage(events, file_name)
    
    def record_load_success(
        self,
        file_name: str,
        file_hour: datetime,
        row_count: int,
        duration_seconds: float,
        file_size_bytes: Optional[int] = None
    ) -> None:
        """
        Record successful file load in LOAD_HISTORY.
        
        Args:
            file_name: File that was loaded
            file_hour: Hour represented by file (UTC datetime)
            row_count: Number of events loaded
            duration_seconds: Time taken to load (seconds)
            file_size_bytes: Optional file size
        """
        cursor = self.connection.cursor()
        try:
            cursor.execute(
                """INSERT INTO RAW.LOAD_HISTORY 
                   (FILE_NAME, FILE_HOUR, ROW_COUNT, STATUS, LOAD_DURATION_SECONDS, FILE_SIZE_BYTES, LOADED_BY)
                   VALUES (%s, %s, %s, 'SUCCESS', %s, %s, CURRENT_USER())""",
                (file_name, file_hour, row_count, duration_seconds, file_size_bytes)
            )
            self.connection.commit()
            logger.info(
                f"Recorded load: {file_name} ({row_count} rows, {duration_seconds:.2f}s)"
            )
        except Exception as e:
            self.connection.rollback()
            logger.error(f"Failed to record load: {e}")
            raise
        finally:
            cursor.close()
    
    def record_load_failure(
        self,
        file_name: str,
        file_hour: datetime,
        error_message: str
    ) -> None:
        """
        Record failed file load attempt.
        
        Args:
            file_name: File that failed to load
            file_hour: Hour represented by file
            error_message: Error details
        """
        cursor = self.connection.cursor()
        try:
            cursor.execute(
                """INSERT INTO RAW.LOAD_HISTORY 
                   (FILE_NAME, FILE_HOUR, ROW_COUNT, STATUS, ERROR_MESSAGE, LOADED_BY)
                   VALUES (%s, %s, 0, 'FAILED', %s, CURRENT_USER())""",
                (file_name, file_hour, error_message[:1000])  # Truncate long errors
            )
            self.connection.commit()
            logger.info(f"Recorded failure: {file_name}")
        except Exception as e:
            self.connection.rollback()
            logger.error(f"Failed to record failure: {e}")
            raise
        finally:
            cursor.close()
    
    def close(self):
        """Close connection."""
        self.connection.close()
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, *args):
        """Context manager exit."""
        self.close()
