-- Run once PER ENVIRONMENT in Snowsight (as ACCOUNTADMIN or a role with CREATE
-- privileges). Creates the warehouse and one environment's database + base
-- schemas so the Airflow + dbt connection checks pass.
--
--   1. set ENV below to 'DEV', run the file
--   2. set ENV to 'PROD', run it again
--
-- The physical database is ANALYTICS_DB_<ENV>; dbt and the Airflow DAG derive
-- the same name from SNOWFLAKE_DATABASE + DBT_TARGET.

SET env = 'DEV';                                  -- 'DEV' or 'PROD'
SET db  = 'ANALYTICS_DB_' || $env;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS IDENTIFIER($db);
USE DATABASE IDENTIFIER($db);

-- Raw landing zone for Airflow extracts.
CREATE SCHEMA IF NOT EXISTS RAW;

-- dbt build target (staging/marts models get their own suffixed schemas:
-- ANALYTICS_STAGING, ANALYTICS_MARTS — dbt creates those automatically).
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
