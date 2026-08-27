-- Refresh ANALYTICS_DB_DEV as a zero-copy clone of ANALYTICS_DB_PROD.
--
-- Instant and effectively free — Snowflake only stores blocks that diverge
-- afterwards. Use it to test models/pipeline changes against prod-shaped data
-- without re-running the whole extract+load.
--
-- WARNING: CREATE OR REPLACE drops the existing dev database. Anything only in
-- dev (a work-in-progress model build, a CI schema) is lost. Grants on the
-- database may need re-applying afterwards.
--
--   snow sql -f snowflake/clone_dev.sql

CREATE OR REPLACE DATABASE ANALYTICS_DB_DEV CLONE ANALYTICS_DB_PROD;
