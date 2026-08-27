-- Run once in Snowsight (as ACCOUNTADMIN or a role with CREATE privileges).
-- Creates the objects the .env expects so Airflow + dbt connection checks pass.

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS ANALYTICS_DB;

-- Raw landing zone for Airflow extracts.
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.RAW;

-- dbt build target (staging/marts models get their own suffixed schemas:
-- ANALYTICS_STAGING, ANALYTICS_MARTS — dbt creates those automatically).
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.ANALYTICS;
