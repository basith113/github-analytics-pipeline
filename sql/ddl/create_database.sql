-- ============================================================
-- GitHub Analytics Pipeline - Database & Schema Setup
-- Phase 2: Snowflake Foundation
-- ============================================================
-- 
-- Purpose: Create GITHUB_DBT database with three schemas:
--   1. RAW - Stores extracted data from GH Archive
--   2. STAGING - Cleaned and flattened data
--   3. MARTS - Optimized dimensional and fact tables
--
-- Data Flow: GH Archive → RAW → STAGING → MARTS → Power BI
--
-- ============================================================

-- Set default warehouse for this session
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- 1. Create Main Database
-- ============================================================
-- 
-- GITHUB_DBT: Main database for all analytics data
--
-- Settings:
--   - TIME_TRAVEL: 1 day (query historical data)
--   - FAIL_SAFE: 7 days (Snowflake automatic backup)
--   - COMMENT: Self-documenting

CREATE DATABASE IF NOT EXISTS GITHUB_DBT
  COMMENT = 'GitHub Analytics Pipeline - End-to-end event data warehouse'
  DATA_RETENTION_TIME_IN_DAYS = 1
  MAX_DATA_EXTENSION_TIME_IN_DAYS = 7;

-- Set active database
USE DATABASE GITHUB_DBT;

-- ============================================================
-- 2. Create RAW Schema
-- ============================================================
-- 
-- Purpose: Store raw, unprocessed data directly from GH Archive
-- Characteristics:
--   - Minimal transformation (only decompression and JSON parsing)
--   - Full event history with JSON variant
--   - Metadata tracking for deduplication
--   - Audit trail of all loads

CREATE SCHEMA IF NOT EXISTS RAW
  COMMENT = 'Raw data layer - Stores unprocessed GitHub events from GH Archive'
  DATA_RETENTION_TIME_IN_DAYS = 1;

-- ============================================================
-- 3. Create STAGING Schema
-- ============================================================
--
-- Purpose: Intermediate transformation layer
-- Characteristics:
--   - Flatten JSON into tabular format
--   - Extract and normalize key fields
--   - Apply business logic and calculations
--   - Add data quality checks
--
-- Models:
--   - stg_github_events: Flattened event data

CREATE SCHEMA IF NOT EXISTS STAGING
  COMMENT = 'Staging layer - Cleaned, flattened, and normalized data'
  DATA_RETENTION_TIME_IN_DAYS = 1;

-- ============================================================
-- 4. Create MARTS Schema
-- ============================================================
--
-- Purpose: Analytics-ready data for reporting
-- Characteristics:
--   - Dimensional models (dimensions)
--   - Fact tables (metrics)
--   - Optimized for query performance
--   - Star schema design
--
-- Models:
--   Dimensions:
--     - dim_actor: GitHub users/bots
--     - dim_repository: GitHub repositories
--     - dim_event_type: Event categories
--   
--   Facts:
--     - fact_events: All events (grain: one row per event)
--     - fact_push_events: Push events only (incremental)

CREATE SCHEMA IF NOT EXISTS MARTS
  COMMENT = 'Mart layer - Optimized dimensional and fact tables for analytics'
  DATA_RETENTION_TIME_IN_DAYS = 7;

-- ============================================================
-- 5. Verify Setup
-- ============================================================

-- Show created database
SHOW DATABASES LIKE 'GITHUB_DBT';

-- Show created schemas
USE DATABASE GITHUB_DBT;
SHOW SCHEMAS;

-- Display summary
SELECT 
  'Database Setup Complete' AS Status,
  'GITHUB_DBT' AS Database,
  'RAW, STAGING, MARTS' AS Schemas,
  CURRENT_TIMESTAMP() AS Timestamp;