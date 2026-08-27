-- Property & Casualty insurance business model (source system).
--
-- Runs once on first startup of the source_postgres container (empty data dir).
-- To (re)apply to a running container (use the SOURCE_POSTGRES_* values from .env):
--   docker compose exec -T source_postgres psql -U insurance_app -d insurance \
--     -f /docker-entrypoint-initdb.d/02_insurance_schema.sql
--
-- Tables (parent -> child):
--   customers, agents, products
--     policies            (customer_id, agent_id, product_id)
--       premium_payments  (policy_id)
--       claims            (policy_id)
--         claim_payments  (claim_id)

CREATE SCHEMA IF NOT EXISTS app;

DROP TABLE IF EXISTS app.claim_payments   CASCADE;
DROP TABLE IF EXISTS app.claims           CASCADE;
DROP TABLE IF EXISTS app.premium_payments CASCADE;
DROP TABLE IF EXISTS app.policies         CASCADE;
DROP TABLE IF EXISTS app.products         CASCADE;
DROP TABLE IF EXISTS app.agents           CASCADE;
DROP TABLE IF EXISTS app.customers        CASCADE;

-- --- Parties ----------------------------------------------------------------
CREATE TABLE app.customers (
    customer_id    BIGINT      PRIMARY KEY,
    first_name     TEXT        NOT NULL,
    last_name      TEXT        NOT NULL,
    email          TEXT        NOT NULL UNIQUE,
    phone          TEXT        NOT NULL,
    date_of_birth  DATE        NOT NULL,
    gender         TEXT        NOT NULL,
    address_line1  TEXT        NOT NULL,
    city           TEXT        NOT NULL,
    state          TEXT        NOT NULL,
    postal_code    TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL
);

CREATE TABLE app.agents (
    agent_id         BIGINT       PRIMARY KEY,
    first_name       TEXT         NOT NULL,
    last_name        TEXT         NOT NULL,
    email            TEXT         NOT NULL UNIQUE,
    hire_date        DATE         NOT NULL,
    region           TEXT         NOT NULL,
    commission_rate  NUMERIC(4,3) NOT NULL,
    is_active        BOOLEAN      NOT NULL
);

-- --- Product catalogue -----------------------------------------------------
CREATE TABLE app.products (
    product_id           BIGINT         PRIMARY KEY,
    product_code         TEXT           NOT NULL UNIQUE,
    product_name         TEXT           NOT NULL,
    line_of_business     TEXT           NOT NULL,  -- AUTO / HOME / LIFE / UMBRELLA
    base_annual_premium  NUMERIC(10,2)  NOT NULL
);

-- --- Policies ------------------------------------------------------------
CREATE TABLE app.policies (
    policy_id          BIGINT        PRIMARY KEY,
    policy_number      TEXT          NOT NULL UNIQUE,
    customer_id        BIGINT        NOT NULL REFERENCES app.customers(customer_id),
    agent_id           BIGINT        NOT NULL REFERENCES app.agents(agent_id),
    product_id         BIGINT        NOT NULL REFERENCES app.products(product_id),
    status             TEXT          NOT NULL,  -- ACTIVE / EXPIRED / LAPSED / CANCELLED
    effective_date     DATE          NOT NULL,
    expiration_date    DATE          NOT NULL,
    annual_premium     NUMERIC(10,2) NOT NULL,
    payment_frequency  TEXT          NOT NULL,  -- ANNUAL / SEMIANNUAL / QUARTERLY / MONTHLY
    created_at         TIMESTAMPTZ   NOT NULL
);

CREATE INDEX ix_policies_customer_id ON app.policies(customer_id);
CREATE INDEX ix_policies_agent_id    ON app.policies(agent_id);

-- --- Premium billing ---------------------------------------------------
CREATE TABLE app.premium_payments (
    premium_payment_id  BIGINT        PRIMARY KEY,
    policy_id           BIGINT        NOT NULL REFERENCES app.policies(policy_id),
    installment_number  INT           NOT NULL,
    due_date            DATE          NOT NULL,
    paid_date           DATE,
    amount              NUMERIC(10,2) NOT NULL,
    method              TEXT,                    -- CARD / ACH / CHECK / CASH
    status              TEXT          NOT NULL   -- PAID / PENDING / LATE / FAILED
);

CREATE INDEX ix_premium_payments_policy_id ON app.premium_payments(policy_id);

-- --- Claims -----------------------------------------------------------
CREATE TABLE app.claims (
    claim_id          BIGINT        PRIMARY KEY,
    claim_number      TEXT          NOT NULL UNIQUE,
    policy_id         BIGINT        NOT NULL REFERENCES app.policies(policy_id),
    claim_type        TEXT          NOT NULL,  -- COLLISION / THEFT / FIRE / ...
    status            TEXT          NOT NULL,  -- OPEN / IN_REVIEW / APPROVED / DENIED / CLOSED
    incident_date     DATE          NOT NULL,
    reported_date     DATE          NOT NULL,
    closed_date       DATE,
    estimated_amount  NUMERIC(12,2) NOT NULL,
    paid_amount       NUMERIC(12,2) NOT NULL,
    description       TEXT          NOT NULL
);

CREATE INDEX ix_claims_policy_id ON app.claims(policy_id);

CREATE TABLE app.claim_payments (
    claim_payment_id  BIGINT        PRIMARY KEY,
    claim_id          BIGINT        NOT NULL REFERENCES app.claims(claim_id),
    payment_date      DATE          NOT NULL,
    amount            NUMERIC(12,2) NOT NULL,
    payment_type      TEXT          NOT NULL,  -- INDEMNITY / EXPENSE
    payee_name        TEXT          NOT NULL
);

CREATE INDEX ix_claim_payments_claim_id ON app.claim_payments(claim_id);
