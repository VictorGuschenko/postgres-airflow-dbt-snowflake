# postgres-airflow-dbt-snowflake

A hands-on **learning project for the modern data stack**. A fictional Property &
Casualty insurer's data flows from an operational Postgres database into
Snowflake and is modelled with dbt, orchestrated by Airflow, all running locally
on Docker.

```
source_postgres          Airflow DAG: postgres_to_snowflake                 Snowflake (ANALYTICS_DB_<ENV>)
  schema app     ──►  extract_to_files ──► upload_to_stage ──► copy_into_raw ──►  RAW.*         (1:1 copy)
  9 tables            (Parquet →           (PUT →              (TRUNCATE +          │
  ~1k policies         ./data)              @RAW.AIRFLOW_STAGE)  COPY INTO)         ▼
                                                              dbt_run ──────────►  ANALYTICS_STAGING  (stg_* views)
                                                              dbt_test ─────────►  ANALYTICS_MARTS    (dim_/fct_ tables)
```

[View the interactive diagram](https://app.diagrams.net/?lightbox=1&highlight=0000ff&layers=1&nav=1#Uhttps%3A%2F%2Fraw.githubusercontent.com%2FVictorGuschenko%2Fpostgres-airflow-dbt-snowflake%2Fmain%2Fdocs%2Fdiagrams%2Fdata_workflow.drawio)
(source: [`docs/diagrams/data_workflow.drawio`](docs/diagrams/data_workflow.drawio), opens in draw.io)

**What you practise here:** containerised orchestration, an ELT (not ETL)
pattern, loading Snowflake from an internal stage, why Parquet beats CSV for
type-faithful loads, and a small but complete dbt project (sources → staging →
marts) with data tests.

## Quickstart

Needs Docker Desktop and a Snowflake account
([free trial](https://signup.snowflake.com/) is enough) plus ~4 GB disk for the
images. The [walkthrough](docs/walkthrough.md) is the same steps, explained.

```bash
git clone <this repo> && cd postgres-airflow-dbt-snowflake
cp .env.example .env
# edit .env: FERNET_KEY, HOST_PROJECT_DIR, SNOWFLAKE_ACCOUNT/USER/PASSWORD, the change-me passwords

# Snowflake objects — dev database + RAW tables/stage (Snowsight, or the snow CLI)
snow sql -f snowflake/bootstrap.sql
snow sql -f snowflake/raw_tables.sql

# local stack
docker compose build
docker compose up -d
./scripts/check_connections.sh     # all 5 hops green?

# run the pipeline
docker compose exec airflow-scheduler airflow dags unpause postgres_to_snowflake
docker compose exec airflow-scheduler airflow dags trigger postgres_to_snowflake
```

Airflow UI: <http://localhost:8080>. A green run ends with `dbt test` `PASS=81`.

## Docs

| | |
| --- | --- |
| [docs/walkthrough.md](docs/walkthrough.md) | Reproduce it from scratch, phase by phase, with the *why* behind each step |
| [docs/architecture.md](docs/architecture.md) | What's in the box — containers, source domain, Snowflake objects, the dbt project, the DAG, repo layout, troubleshooting |
| [docs/environments.md](docs/environments.md) | dev / prod isolation via `DBT_TARGET`, and the CI workflow |
| [docs/design-notes.md](docs/design-notes.md) | Why Parquet not CSV, ELT vs ETL, deterministic seed data |

## Status & next steps

- [x] Local stack (Postgres + Airflow + dbt on Compose)
- [x] Snowflake bootstrap + `RAW` tables / stage / file format
- [x] P&C insurance source schema + deterministic mimic data (~1k policies)
- [x] `postgres_to_snowflake` DAG: extract → stage → `COPY` → dbt
- [x] dbt project: 9 staging views, 7 marts, ~80 tests
- [x] End-to-end run green (`dbt run` PASS=16, `dbt test` PASS=81)
- [x] Quote funnel + coverage line items (`fct_quotes`, `fct_coverages`, `fct_agent_performance`)
- [x] dev / prod environment split (`DBT_TARGET` → `ANALYTICS_DB_<ENV>`)
- [x] Offline CI (lint, DAG import, `dbt parse` + `sqlfluff`)
- [ ] Warehouse-connected CI: `dbt build` on a per-PR schema, Slim CI with a stored prod manifest
- [ ] Incremental / CDC load instead of full snapshot
- [ ] A schedule + SLAs
- [ ] `dbt source freshness` + `dbt docs` served somewhere
