# Environments (dev / prod) and CI

## dev / prod

One variable — `DBT_TARGET` (`dev` | `prod`, default `dev`) — selects a fully
isolated Snowflake **database** for the whole pipeline:

```
DBT_TARGET=dev   →  ANALYTICS_DB_DEV   (RAW, ANALYTICS_STAGING, ANALYTICS_MARTS)
DBT_TARGET=prod  →  ANALYTICS_DB_PROD  (same schemas)
```

Both share the account, warehouse and role; only the database differs. How it
threads through:

| Consumer | Mechanism |
| --- | --- |
| Airflow DAG | `DBT_TARGET` → `RAW_DATABASE = f"{SNOWFLAKE_DATABASE}_{DBT_TARGET.upper()}"`; every `COPY`/`PUT`/`TRUNCATE` is fully qualified |
| dbt models | `macros/generate_database_name.sql` → `<SNOWFLAKE_DATABASE>_<target>` |
| dbt sources | `_staging__sources.yml`: `database: "{{ env_var('SNOWFLAKE_DATABASE') }}_{{ target.name \| upper }}"` |
| dbt target | `profiles.yml`: `target: "{{ env_var('DBT_TARGET', 'dev') }}"`, plus `--target` passed by the DAG |
| Airflow connection | `docker-compose.yaml` sets the connection's default database to `${SNOWFLAKE_DATABASE}_${DBT_TARGET}` |

`SNOWFLAKE_DATABASE` in `.env` stays the **base** name (`ANALYTICS_DB`).

Git branches and environments are **separate axes** — there is no `dev` or `prod`
branch. `main` is the single source of truth; you pick the environment with
`DBT_TARGET` at run time.

### Setup per environment

Run twice, editing `env` at the top of each file:

```bash
# env = 'DEV', then env = 'PROD'
snow sql -f snowflake/bootstrap.sql
snow sql -f snowflake/raw_tables.sql
```

### Working locally

Keep `DBT_TARGET=dev`. Refresh dev with prod-shaped data any time via a
zero-copy clone (instant, no storage cost):

```bash
snow sql -f snowflake/clone_dev.sql   # CREATE OR REPLACE DATABASE ANALYTICS_DB_DEV CLONE ANALYTICS_DB_PROD
```

### Promoting to prod

Since Airflow is local here, "deploy" = run the DAG (or `dbt build`) with
`DBT_TARGET=prod`:

```bash
DBT_TARGET=prod docker compose run --rm dbt build
# or set DBT_TARGET=prod and trigger the DAG
```

Typical loop: feature branch → PR → CI green → merge to `main` → `git pull` →
run with `DBT_TARGET=dev` and check → run with `DBT_TARGET=prod`. In a hosted
setup that variable would be set on the prod Airflow deployment and CD would ship
code, not run transforms.

## CI (`.github/workflows/ci.yml`)

Runs on every PR and push to `main`. **Offline only** — no Snowflake connection:

| Job | Checks |
| --- | --- |
| `lint` | `ruff` on Python (`ruff.toml`), `yamllint` on dbt/workflow YAML (`.yamllint`) |
| `dags` | Builds the project Airflow image, asserts `DagBag` has no import errors |
| `dbt` | `dbt deps` + `dbt parse` (refs, Jinja, YAML, sources), then `sqlfluff lint` on models (`.sqlfluff`, jinja templater with dbt built-ins stubbed) |

`dbt parse` uses dummy `SNOWFLAKE_*` values — it renders `profiles.yml` but never
connects. Warehouse-connected checks (`dbt build` against a per-PR schema, Slim
CI with a stored prod manifest) are a planned follow-up as a separate workflow.
