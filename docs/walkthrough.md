# Walkthrough — reproduce it from scratch

Each phase says **what** to do and **why** it matters. For the component
reference (containers, tables, models), see [architecture.md](architecture.md).

## Phase 1 — Bring up the local stack

```bash
git clone <this repo> && cd postgres-airflow-dbt-snowflake
cp .env.example .env
```

Edit `.env`:

| Variable | How to set it |
| --- | --- |
| `HOST_PROJECT_DIR` | Absolute path to this repo. The `DockerOperator` needs it to bind-mount `./dbt` into the dbt container it starts on the host. |
| `FERNET_KEY` | `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"` — encrypts Airflow connection secrets. |
| `_AIRFLOW_WWW_USER_PASSWORD`, `SOURCE_POSTGRES_PASSWORD` | Replace the `change-me` placeholders. Keep `AIRFLOW_CONN_SOURCE_POSTGRES` in sync with the `SOURCE_POSTGRES_*` values. |
| `SNOWFLAKE_ACCOUNT` / `SNOWFLAKE_USER` / `SNOWFLAKE_PASSWORD` | Your Snowflake login. **These live in exactly one place** — `docker-compose.yaml` assembles the Airflow `snowflake_default` connection from them, and dbt's `profiles.yml` reads the same variables. |

```bash
docker compose build          # builds the custom airflow + dbt images
docker compose up -d
docker compose ps             # wait until every service is "healthy"
```

*Why a custom Airflow image?* It bakes in the `postgres`, `snowflake`, and
`docker` providers plus `pandas`/`pyarrow` (see `airflow/requirements.txt`).
*Why `LocalExecutor`?* One machine, no need for Celery/Redis; tasks run as
subprocesses of the scheduler.

Airflow UI: <http://localhost:8080> (the `_AIRFLOW_WWW_USER_*` values from
`.env`; `.env.example` ships `admin` / `change-me`).

## Phase 2 — Create the Snowflake objects

Both files carry `SET env = 'DEV';` at the top. For local work you only need the
`DEV` database; run each file again with `env` set to `PROD` when you want prod.

```bash
snow sql -f snowflake/bootstrap.sql     # warehouse + ANALYTICS_DB_DEV, RAW + ANALYTICS schemas
snow sql -f snowflake/raw_tables.sql    # RAW.* tables, AIRFLOW_STAGE, PARQUET_FORMAT
```

(or paste both files into Snowsight). `raw_tables.sql` is safe to re-run —
tables are `CREATE OR REPLACE`, the stage/format are `CREATE … IF NOT EXISTS`.
See [environments.md](environments.md) for the full picture.

*Why declare `RAW.*` by hand* instead of letting `COPY` infer them? A "one-to-one"
load means **you** own the target types. `bigint → NUMBER(38,0)`,
`numeric(p,s) → NUMBER(p,s)`, `timestamptz → TIMESTAMP_TZ`, etc. Inference would
guess, and guesses drift between runs.

## Phase 3 — Verify every connection

```bash
docker compose exec airflow-scheduler bash -lc 'airflow db check'   # metadata DB
./scripts/check_connections.sh                                       # all 5 hops
```

`check_connections.sh` proves: Airflow → metadata Postgres, Airflow →
`source_postgres`, Airflow → Snowflake, Airflow → the host Docker daemon (needed
for `DockerOperator`), and dbt → Snowflake (`dbt debug`). Fix any red line here
before running the DAG.

## Phase 4 — Understand the source data

`postgres/init/*.sql` runs **once**, automatically, the first time
`source_postgres` starts with an empty data directory:

| File | Purpose |
| --- | --- |
| `01_init.sql` | creates schema `app` |
| `02_insurance_schema.sql` | the core 7 tables, PKs, FKs, indexes |
| `03_insurance_seed.sql` | `setseed(0.4242)` + deterministic `INSERT … SELECT generate_series(...)` |
| `04_extra_schema.sql` | `quotes` + `coverages` |
| `05_extra_seed.sql` | deterministic data for those two |

To regenerate on an already-running container (the init hook won't fire again):

```bash
# use the SOURCE_POSTGRES_* user / db you set in .env (.env.example: insurance_app / insurance)
for f in 02_insurance_schema 03_insurance_seed 04_extra_schema 05_extra_seed; do
  docker compose exec -T source_postgres psql -U insurance_app -d insurance \
    -f /docker-entrypoint-initdb.d/$f.sql
done
```

To start completely fresh: `docker compose down -v` (drops the volumes) then
`docker compose up -d`.

Poke around:

```bash
docker compose exec source_postgres psql -U insurance_app -d insurance
# \dt app.*
# SELECT status, count(*) FROM app.policies GROUP BY 1;
```

## Phase 5 — Read the DAG before you run it

Open `airflow/dags/postgres_to_snowflake.py`. Things worth noticing:

- **`TABLES`** is the whole configuration — `{"app.customers": "CUSTOMERS", …}`.
  Add a source table by adding a line (and a matching `RAW` table + `stg_` model).
- **`DBT_TARGET`** (`dev` | `prod`) picks `RAW_DATABASE = f"{SNOWFLAKE_DATABASE}_{DBT_TARGET.upper()}"`
  and is passed on to the dbt tasks. See [environments.md](environments.md).
- **XCom manifest.** `extract_to_files` returns `{target: filename}`; the next
  two tasks consume it. No global state, no filename guessing.
- **`AUTO_COMPRESS=FALSE`.** Parquet is already compressed; keeping the name
  stable lets `COPY` address the exact file (`@stage/CUSTOMERS_<ts>.parquet`)
  instead of a `PATTERN`.
- **`TRUNCATE` + `COPY`.** This is a *full snapshot* load — simple and idempotent
  for a learning project. Incremental loading is a later exercise.
- **`MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE`.** Parquet field names (lowercase,
  from pandas) match the uppercase Snowflake columns; the extra `_loaded_at`
  column just takes its `DEFAULT`.

## Phase 6 — Run the pipeline

From the UI: unpause **`postgres_to_snowflake`**, hit ▶ *Trigger*.

Or from the CLI:

```bash
docker compose exec airflow-scheduler airflow dags unpause postgres_to_snowflake
docker compose exec airflow-scheduler airflow dags trigger postgres_to_snowflake

# watch it
docker compose exec airflow-scheduler \
  airflow tasks states-for-dag-run postgres_to_snowflake <run_id>
```

A green run ends with `dbt run` `PASS=16` and `dbt test` `PASS=81`.

## Phase 7 — Explore the results in Snowflake

```sql
USE DATABASE ANALYTICS_DB_DEV;

-- RAW is a byte-for-byte copy of Postgres
SELECT 'RAW' AS layer, table_name, row_count
FROM INFORMATION_SCHEMA.TABLES WHERE table_schema = 'RAW';

-- staging = renamed views, marts = modelled tables
SELECT * FROM ANALYTICS_MARTS.DIM_POLICIES LIMIT 20;

SELECT line_of_business,
       count(*)                    AS claims,
       round(sum(paid_amount))     AS paid,
       round(avg(days_to_close),1) AS avg_days_to_close
FROM ANALYTICS_MARTS.FCT_CLAIMS
GROUP BY 1 ORDER BY paid DESC;

-- agent funnel
SELECT agent_name, quote_count, quote_conversion_rate,
       policy_count, estimated_annual_commission
FROM ANALYTICS_MARTS.FCT_AGENT_PERFORMANCE
ORDER BY written_annual_premium DESC LIMIT 10;
```

## Phase 8 — Change something (exercises)

1. **Add a column** to `app.customers` (e.g. `marital_status`), reseed, add it to
   `RAW.CUSTOMERS`, `stg_customers`, `dim_customers`. Re-run the DAG.
2. **Add a mart** — a `dim_customer_cohort` or a monthly `fct_policy_snapshot`.
   Add tests.
3. **Make `RAW` incremental** — switch `copy_into_raw` from `TRUNCATE`+`COPY` to
   an `updated_at` high-water mark and a `MERGE`. You'll need an `updated_at`
   column in the source.
4. **Schedule it** — set `schedule="@daily"` and `catchup=False`, observe runs.
5. **Break a test** — change a seed value so the reconciliation test fails, and
   watch `dbt_test` turn the DAG red.
6. **Promote to prod** — bootstrap `ANALYTICS_DB_PROD`, then run with
   `DBT_TARGET=prod` (see [environments.md](environments.md)).
