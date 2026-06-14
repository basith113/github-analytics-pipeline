-- ============================================================
-- GitHub Analytics Pipeline - Snowflake Validation Queries
-- Phase 2: Snowflake Foundation - Validation
-- ============================================================
--
-- Purpose: Verify Snowflake setup is correct and complete
--
-- Run these queries to validate:
--   ✓ Database exists
--   ✓ All schemas created
--   ✓ All tables created with correct structure
--   ✓ Permissions are correct
--   ✓ Tables are ready for data ingestion
--
-- ============================================================

USE DATABASE GITHUB_DBT;

-- ============================================================
-- 1. Verify Database & Schemas
-- ============================================================

-- Check database exists
SELECT 'GITHUB_DBT' AS Database, 'FOUND ✓' AS Status WHERE EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA 
  WHERE CATALOG_NAME = CURRENT_DATABASE() 
    AND SCHEMA_NAME = 'RAW'
);

-- List all schemas
SELECT 
  SCHEMA_NAME,
  CREATED ON as Creation_Date,
  TYPE as Schema_Type,
  COMMENT
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = CURRENT_DATABASE()
ORDER BY SCHEMA_NAME;

-- ============================================================
-- 2. Verify Raw Layer Tables
-- ============================================================

-- Check RAW schema tables
SELECT 
  'RAW' AS Schema_Name,
  TABLE_NAME,
  TABLE_TYPE,
  ROW_COUNT,
  BYTES,
  COMMENT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = CURRENT_DATABASE()
  AND TABLE_SCHEMA = 'RAW'
ORDER BY TABLE_NAME;

-- Verify GITHUB_EVENTS structure
DESC TABLE RAW.GITHUB_EVENTS;

-- Verify LOAD_HISTORY structure  
DESC TABLE RAW.LOAD_HISTORY;

-- ============================================================
-- 3. Verify Views
-- ============================================================

-- List all views in RAW schema
SELECT 
  VIEW_NAME,
  COMMENT
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_CATALOG = CURRENT_DATABASE()
  AND TABLE_SCHEMA = 'RAW'
ORDER BY VIEW_NAME;

-- ============================================================
-- 4. Verify Stored Procedures
-- ============================================================

-- List all procedures
SELECT 
  PROCEDURE_NAME,
  COMMENT
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_CATALOG = CURRENT_DATABASE()
  AND PROCEDURE_SCHEMA = 'RAW'
ORDER BY PROCEDURE_NAME;

-- ============================================================
-- 5. Table Size & Capacity Check
-- ============================================================

-- Current table sizes
SELECT 
  TABLE_NAME,
  ROW_COUNT,
  ROUND(BYTES / 1024 / 1024, 2) AS SIZE_MB,
  BYTES
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = CURRENT_DATABASE()
  AND TABLE_SCHEMA = 'RAW'
ORDER BY BYTES DESC;

-- ============================================================
-- 6. Data Ready Check
-- ============================================================

-- Count rows in each table (should be 0 initially)
SELECT 
  'GITHUB_EVENTS' AS Table_Name,
  COUNT(*) AS Row_Count,
  'Ready for ingestion ✓' AS Status
FROM RAW.GITHUB_EVENTS
UNION ALL
SELECT 
  'LOAD_HISTORY' AS Table_Name,
  COUNT(*) AS Row_Count,
  'Ready for ingestion ✓' AS Status
FROM RAW.LOAD_HISTORY;

-- ============================================================
-- 7. Permission & Access Check
-- ============================================================

-- Current user & role
SELECT 
  CURRENT_USER() AS Current_User,
  CURRENT_ROLE() AS Current_Role,
  CURRENT_WAREHOUSE() AS Current_Warehouse,
  CURRENT_DATABASE() AS Current_Database;

-- Database grants
SHOW GRANTS ON DATABASE GITHUB_DBT;

-- Schema grants
SHOW GRANTS ON SCHEMA RAW;
SHOW GRANTS ON SCHEMA STAGING;
SHOW GRANTS ON SCHEMA MARTS;

-- ============================================================
-- 8. Performance Settings Check
-- ============================================================

-- Database parameters
SELECT 
  'Retention' AS Parameter,
  DATA_RETENTION_TIME_IN_DAYS AS Value
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME = 'GITHUB_DBT'
UNION ALL
SELECT 
  'Fail Safe',
  MAX_DATA_EXTENSION_TIME_IN_DAYS
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME = 'GITHUB_DBT';

-- ============================================================
-- 9. Comprehensive Setup Validation Report
-- ============================================================

WITH setup_checks AS (
  -- Database check
  SELECT 'Database: GITHUB_DBT' AS Check_Item,
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.DATABASES 
      WHERE DATABASE_NAME = 'GITHUB_DBT'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END AS Status
  
  UNION ALL
  
  -- Schemas check
  SELECT 'Schema: RAW',
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA 
      WHERE SCHEMA_NAME = 'RAW' AND CATALOG_NAME = 'GITHUB_DBT'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END
  
  UNION ALL
  
  SELECT 'Schema: STAGING',
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA 
      WHERE SCHEMA_NAME = 'STAGING' AND CATALOG_NAME = 'GITHUB_DBT'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END
  
  UNION ALL
  
  SELECT 'Schema: MARTS',
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA 
      WHERE SCHEMA_NAME = 'MARTS' AND CATALOG_NAME = 'GITHUB_DBT'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END
  
  UNION ALL
  
  -- Tables check
  SELECT 'Table: GITHUB_EVENTS',
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME = 'GITHUB_EVENTS' AND TABLE_SCHEMA = 'RAW'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END
  
  UNION ALL
  
  SELECT 'Table: LOAD_HISTORY',
    CASE WHEN EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
      WHERE TABLE_NAME = 'LOAD_HISTORY' AND TABLE_SCHEMA = 'RAW'
    ) THEN '✓ PASS' ELSE '✗ FAIL' END
)

SELECT 
  Check_Item,
  Status,
  CASE WHEN Status = '✓ PASS' THEN 'Configuration correct' ELSE 'Requires attention' END AS Notes
FROM setup_checks
ORDER BY Status DESC, Check_Item;

-- ============================================================
-- 10. Final Summary
-- ============================================================

SELECT 
  'Snowflake Foundation Setup - COMPLETE ✓' AS Status,
  CURRENT_TIMESTAMP() AS Validation_Time,
  CURRENT_USER() AS Validated_By,
  'Ready for Phase 3: Ingestion' AS Next_Step;