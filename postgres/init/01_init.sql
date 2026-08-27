-- Runs once on first startup of the source_postgres container (empty data dir).
-- Put the business schema + mimic/seed data here once the domain is defined.

CREATE SCHEMA IF NOT EXISTS app;

-- Example placeholder — replace with the real model:
-- CREATE TABLE app.customers (
--     id          BIGSERIAL PRIMARY KEY,
--     email       TEXT NOT NULL UNIQUE,
--     created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
-- );
