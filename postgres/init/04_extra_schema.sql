-- Additional P&C source tables (phase 2): the pre-policy quote funnel and
-- per-policy coverage line items.
--
-- Runs once on first startup of the source_postgres container. To (re)apply to
-- a running container (use the SOURCE_POSTGRES_* values from .env):
--   docker compose exec -T source_postgres psql -U insurance_app -d insurance \
--     -f /docker-entrypoint-initdb.d/04_extra_schema.sql
--
--   customers/agents/products
--     quotes              (customer_id, agent_id, product_id, converted_policy_id?)
--   policies
--     coverages           (policy_id)  -- premium_amount sums to policies.annual_premium

DROP TABLE IF EXISTS app.coverages CASCADE;
DROP TABLE IF EXISTS app.quotes    CASCADE;

-- --- Quote funnel --------------------------------------------------------
CREATE TABLE app.quotes (
    quote_id               BIGINT        PRIMARY KEY,
    quote_number           TEXT          NOT NULL UNIQUE,
    customer_id            BIGINT        NOT NULL REFERENCES app.customers(customer_id),
    agent_id               BIGINT        NOT NULL REFERENCES app.agents(agent_id),
    product_id             BIGINT        NOT NULL REFERENCES app.products(product_id),
    status                 TEXT          NOT NULL,  -- DRAFT / SENT / ACCEPTED / DECLINED / EXPIRED
    quoted_annual_premium  NUMERIC(10,2) NOT NULL,
    created_at             TIMESTAMPTZ   NOT NULL,
    decision_date          DATE,                    -- set when accepted / declined / expired
    converted_policy_id    BIGINT        REFERENCES app.policies(policy_id)  -- set iff ACCEPTED
);

CREATE INDEX ix_quotes_customer_id          ON app.quotes(customer_id);
CREATE INDEX ix_quotes_converted_policy_id  ON app.quotes(converted_policy_id);

-- --- Coverage line items --------------------------------------------
CREATE TABLE app.coverages (
    coverage_id     BIGINT        PRIMARY KEY,
    policy_id       BIGINT        NOT NULL REFERENCES app.policies(policy_id),
    coverage_code   TEXT          NOT NULL,  -- BODILY_INJURY / DWELLING / DEATH_BENEFIT / ...
    coverage_name   TEXT          NOT NULL,
    limit_amount    NUMERIC(12,2) NOT NULL,
    deductible      NUMERIC(10,2) NOT NULL,
    premium_amount  NUMERIC(10,2) NOT NULL,
    UNIQUE (policy_id, coverage_code)
);

CREATE INDEX ix_coverages_policy_id ON app.coverages(policy_id);
