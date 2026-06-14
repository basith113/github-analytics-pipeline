#!/usr/bin/env python3
"""
Data Quality Monitoring Script
Checks data quality metrics and generates alerts

Usage:
    python ingestion/utils/data_quality_monitor.py
"""

import os
import sys
import json
import logging
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from snowflake_loader import SnowflakeConnection
from helpers import get_logger, Timer

# Load environment variables
load_dotenv()

# Setup logging
logger = get_logger(__name__)


class DataQualityMonitor:
    """Monitor data quality metrics across all layers"""
    
    def __init__(self):
        self.connection = SnowflakeConnection()
        self.checks = {}
        self.alerts = []
    
    def check_raw_freshness(self, max_age_hours=2):
        """Check if RAW.GITHUB_EVENTS is fresh enough"""
        logger.info(f"Checking RAW data freshness (max age: {max_age_hours}h)")
        
        query = """
        SELECT 
          MAX(LOAD_TS) as last_loaded,
          DATEDIFF('hour', MAX(LOAD_TS), CURRENT_TIMESTAMP()) as hours_behind
        FROM RAW.GITHUB_EVENTS;
        """
        
        result = self.connection.execute(query)
        row = result.fetchone()
        
        if row:
            last_loaded, hours_behind = row
            self.checks['raw_freshness'] = {
                'status': 'FRESH' if hours_behind < max_age_hours else 'STALE',
                'last_loaded': str(last_loaded),
                'hours_behind': hours_behind
            }
            
            if hours_behind >= max_age_hours:
                self.alerts.append({
                    'severity': 'WARNING' if hours_behind < max_age_hours * 2 else 'ERROR',
                    'message': f'RAW data is {hours_behind}h old (max: {max_age_hours}h)'
                })
    
    def check_duplicate_events(self):
        """Check for duplicate events in fact table"""
        logger.info("Checking for duplicate events")
        
        query = """
        SELECT COUNT(*) as duplicate_count
        FROM MARTS.FACT_EVENTS
        GROUP BY event_id
        HAVING COUNT(*) > 1
        LIMIT 1;
        """
        
        result = self.connection.execute(query)
        row = result.fetchone()
        
        dup_count = row[0] if row else 0
        self.checks['duplicates'] = {
            'status': 'OK' if dup_count == 0 else 'FAILED',
            'duplicate_events': dup_count
        }
        
        if dup_count > 0:
            self.alerts.append({
                'severity': 'ERROR',
                'message': f'Found {dup_count} duplicate events in FACT_EVENTS'
            })
    
    def check_missing_dimensions(self):
        """Check for facts missing dimension references"""
        logger.info("Checking dimension references")
        
        query = """
        SELECT 
          COUNT(CASE WHEN actor_key IS NULL THEN 1 END) as missing_actors,
          COUNT(CASE WHEN repo_key IS NULL THEN 1 END) as missing_repos,
          COUNT(CASE WHEN event_type_key IS NULL THEN 1 END) as missing_types
        FROM MARTS.FACT_EVENTS
        WHERE event_key IS NOT NULL;
        """
        
        result = self.connection.execute(query)
        row = result.fetchone()
        
        if row:
            missing_actors, missing_repos, missing_types = row
            self.checks['missing_dimensions'] = {
                'status': 'OK' if all(x == 0 for x in row) else 'FAILED',
                'missing_actor_keys': missing_actors,
                'missing_repo_keys': missing_repos,
                'missing_event_type_keys': missing_types
            }
            
            if any(x > 0 for x in row):
                self.alerts.append({
                    'severity': 'WARNING',
                    'message': f'Missing dimension references: actors={missing_actors}, repos={missing_repos}, types={missing_types}'
                })
    
    def check_event_volume_anomaly(self):
        """Detect unusual event volume changes"""
        logger.info("Checking for volume anomalies")
        
        query = """
        WITH daily_counts AS (
          SELECT 
            DATE(created_at) as event_date,
            COUNT(*) as daily_events
          FROM MARTS.FACT_EVENTS
          WHERE created_at >= CURRENT_DATE - 7
          GROUP BY DATE(created_at)
        )
        
        SELECT 
          event_date,
          daily_events,
          ROUND(AVG(daily_events) OVER (
            ORDER BY event_date 
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
          ), 0) as avg_7day,
          ROUND(daily_events * 100.0 / AVG(daily_events) OVER (
            ORDER BY event_date 
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
          ), 1) as pct_of_avg
        FROM daily_counts
        WHERE event_date = CURRENT_DATE - 1
        ORDER BY event_date DESC
        LIMIT 1;
        """
        
        result = self.connection.execute(query)
        row = result.fetchone()
        
        if row:
            event_date, daily_events, avg_7day, pct_of_avg = row
            
            # Flag if today is <80% or >120% of average
            status = 'OK'
            if pct_of_avg < 80 or pct_of_avg > 120:
                status = 'ANOMALY'
            
            self.checks['volume_anomaly'] = {
                'status': status,
                'date': str(event_date),
                'event_count': daily_events,
                'seven_day_avg': avg_7day,
                'percent_of_avg': pct_of_avg
            }
            
            if status == 'ANOMALY':
                self.alerts.append({
                    'severity': 'WARNING',
                    'message': f'Volume anomaly: {daily_events} events ({pct_of_avg}% of 7-day avg)'
                })
    
    def check_load_failures(self):
        """Check for recent load failures"""
        logger.info("Checking load failures")
        
        query = """
        SELECT COUNT(*) as failure_count
        FROM RAW.LOAD_HISTORY
        WHERE STATUS = 'FAILED'
          AND LOAD_TS >= CURRENT_TIMESTAMP() - INTERVAL '1 hour';
        """
        
        result = self.connection.execute(query)
        row = result.fetchone()
        
        failure_count = row[0] if row else 0
        self.checks['recent_failures'] = {
            'status': 'OK' if failure_count == 0 else 'FAILED',
            'failures_last_hour': failure_count
        }
        
        if failure_count > 0:
            self.alerts.append({
                'severity': 'WARNING',
                'message': f'{failure_count} load failures in last hour'
            })
    
    def run_all_checks(self):
        """Execute all quality checks"""
        logger.info("=" * 60)
        logger.info("Starting Data Quality Monitor")
        logger.info("=" * 60)
        
        with Timer('All Quality Checks', logger):
            self.check_raw_freshness()
            self.check_duplicate_events()
            self.check_missing_dimensions()
            self.check_event_volume_anomaly()
            self.check_load_failures()
        
        return self.generate_report()
    
    def generate_report(self):
        """Generate quality report"""
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'PASS' if not self.alerts else 'FAIL',
            'alert_count': len(self.alerts),
            'checks': self.checks,
            'alerts': self.alerts
        }
        
        logger.info("\n" + "=" * 60)
        logger.info("Data Quality Report")
        logger.info("=" * 60)
        logger.info(json.dumps(report, indent=2))
        logger.info("=" * 60)
        
        return report
    
    def close(self):
        """Clean up connections"""
        self.connection.close()


def main():
    """Main entry point"""
    try:
        monitor = DataQualityMonitor()
        report = monitor.run_all_checks()
        monitor.close()
        
        # Exit with error code if there are alerts
        return 1 if report['alerts'] else 0
    
    except Exception as e:
        logger.error(f"Monitor failed: {e}", exc_info=True)
        return 2


if __name__ == '__main__':
    exit_code = main()
    sys.exit(exit_code)
