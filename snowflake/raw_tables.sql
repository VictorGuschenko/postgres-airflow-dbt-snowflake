-- RAW landing tables for the Airflow Postgres -> Snowflake load.
--
-- One-to-one with the app.* schema in source_postgres
-- (postgres/init/02_insurance_schema.sql). Column names match exactly; the
-- DAG's COPY INTO uses MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE.
--
-- Run in Snowsight AFTER snowflake/bootstrap.sql, once per environment
-- (set ENV to 'DEV', run; set ENV to 'PROD', run again).
--
-- Type mapping:
--   bigint / int          -> NUMBER(38,0)
--   text                  -> VARCHAR
--   numeric(p,s)          -> NUMBER(p,s)
--   date                  -> DATE
--   timestamptz           -> TIMESTAMP_TZ
--   boolean               -> BOOLEAN
-- Primary keys are declared for documentation / dbt; Snowflake does not enforce
-- them (RELY is informational only).

SET env = 'DEV';                                  -- 'DEV' or 'PROD'
USE DATABASE IDENTIFIER('ANALYTICS_DB_' || $env);
USE SCHEMA RAW;

-- ===================== load objects =====================
-- Internal named stage the Airflow DAG PUTs extract files to, then COPY INTO
-- reads from. Name must match SNOWFLAKE_STAGE in
-- airflow/dags/postgres_to_snowflake.py (ANALYTICS_DB_<ENV>.RAW.AIRFLOW_STAGE).
CREATE FILE FORMAT IF NOT EXISTS RAW.PARQUET_FORMAT
    TYPE = PARQUET;

CREATE STAGE IF NOT EXISTS RAW.AIRFLOW_STAGE
    FILE_FORMAT = RAW.PARQUET_FORMAT
    COMMENT = 'Airflow Postgres extract landing stage';

-- ===================== customers =====================
CREATE OR REPLACE TABLE RAW.CUSTOMERS (
    customer_id    NUMBER(38,0)  NOT NULL,
    first_name     VARCHAR       NOT NULL,
    last_name      VARCHAR       NOT NULL,
    email          VARCHAR       NOT NULL,
    phone          VARCHAR       NOT NULL,
    date_of_birth  DATE          NOT NULL,
    gender         VARCHAR       NOT NULL,
    address_line1  VARCHAR       NOT NULL,
    city           VARCHAR       NOT NULL,
    state          VARCHAR       NOT NULL,
    postal_code    VARCHAR       NOT NULL,
    created_at     TIMESTAMP_TZ  NOT NULL,
    _loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

-- ===================== agents =====================
CREATE OR REPLACE TABLE RAW.AGENTS (
    agent_id         NUMBER(38,0)  NOT NULL,
    first_name       VARCHAR       NOT NULL,
    last_name        VARCHAR       NOT NULL,
    email            VARCHAR       NOT NULL,
    hire_date        DATE          NOT NULL,
    region           VARCHAR       NOT NULL,
    commission_rate  NUMBER(4,3)   NOT NULL,
    is_active        BOOLEAN       NOT NULL,
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agents PRIMARY KEY (agent_id)
);

-- ===================== products =====================
CREATE OR REPLACE TABLE RAW.PRODUCTS (
    product_id           NUMBER(38,0)  NOT NULL,
    product_code         VARCHAR       NOT NULL,
    product_name         VARCHAR       NOT NULL,
    line_of_business     VARCHAR       NOT NULL,
    base_annual_premium  NUMBER(10,2)  NOT NULL,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_products PRIMARY KEY (product_id)
);

-- ===================== policies =====================
CREATE OR REPLACE TABLE RAW.POLICIES (
    policy_id          NUMBER(38,0)  NOT NULL,
    policy_number      VARCHAR       NOT NULL,
    customer_id        NUMBER(38,0)  NOT NULL,
    agent_id           NUMBER(38,0)  NOT NULL,
    product_id         NUMBER(38,0)  NOT NULL,
    status             VARCHAR       NOT NULL,
    effective_date     DATE          NOT NULL,
    expiration_date    DATE          NOT NULL,
    annual_premium     NUMBER(10,2)  NOT NULL,
    payment_frequency  VARCHAR       NOT NULL,
    created_at         TIMESTAMP_TZ  NOT NULL,
    _loaded_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_policies PRIMARY KEY (policy_id)
);

-- ===================== premium_payments =====================
CREATE OR REPLACE TABLE RAW.PREMIUM_PAYMENTS (
    premium_payment_id  NUMBER(38,0)  NOT NULL,
    policy_id           NUMBER(38,0)  NOT NULL,
    installment_number  NUMBER(38,0)  NOT NULL,
    due_date            DATE          NOT NULL,
    paid_date           DATE,
    amount              NUMBER(10,2)  NOT NULL,
    method              VARCHAR,
    status              VARCHAR       NOT NULL,
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_premium_payments PRIMARY KEY (premium_payment_id)
);

-- ===================== claims =====================
CREATE OR REPLACE TABLE RAW.CLAIMS (
    claim_id          NUMBER(38,0)  NOT NULL,
    claim_number      VARCHAR       NOT NULL,
    policy_id         NUMBER(38,0)  NOT NULL,
    claim_type        VARCHAR       NOT NULL,
    status            VARCHAR       NOT NULL,
    incident_date     DATE          NOT NULL,
    reported_date     DATE          NOT NULL,
    closed_date       DATE,
    estimated_amount  NUMBER(12,2)  NOT NULL,
    paid_amount       NUMBER(12,2)  NOT NULL,
    description       VARCHAR       NOT NULL,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_claims PRIMARY KEY (claim_id)
);

-- ===================== claim_payments =====================
CREATE OR REPLACE TABLE RAW.CLAIM_PAYMENTS (
    claim_payment_id  NUMBER(38,0)  NOT NULL,
    claim_id          NUMBER(38,0)  NOT NULL,
    payment_date      DATE          NOT NULL,
    amount            NUMBER(12,2)  NOT NULL,
    payment_type      VARCHAR       NOT NULL,
    payee_name        VARCHAR       NOT NULL,
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_claim_payments PRIMARY KEY (claim_payment_id)
);

-- ===================== quotes =====================
CREATE OR REPLACE TABLE RAW.QUOTES (
    quote_id               NUMBER(38,0)  NOT NULL,
    quote_number           VARCHAR       NOT NULL,
    customer_id            NUMBER(38,0)  NOT NULL,
    agent_id               NUMBER(38,0)  NOT NULL,
    product_id             NUMBER(38,0)  NOT NULL,
    status                 VARCHAR       NOT NULL,
    quoted_annual_premium  NUMBER(10,2)  NOT NULL,
    created_at             TIMESTAMP_TZ  NOT NULL,
    decision_date          DATE,
    converted_policy_id    NUMBER(38,0),
    _loaded_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_quotes PRIMARY KEY (quote_id)
);

-- ===================== coverages =====================
CREATE OR REPLACE TABLE RAW.COVERAGES (
    coverage_id     NUMBER(38,0)  NOT NULL,
    policy_id       NUMBER(38,0)  NOT NULL,
    coverage_code   VARCHAR       NOT NULL,
    coverage_name   VARCHAR       NOT NULL,
    limit_amount    NUMBER(12,2)  NOT NULL,
    deductible      NUMBER(10,2)  NOT NULL,
    premium_amount  NUMBER(10,2)  NOT NULL,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_coverages PRIMARY KEY (coverage_id)
);
