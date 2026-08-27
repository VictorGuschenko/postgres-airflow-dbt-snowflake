# postgres-airflow-dbt-snowflake

Learning project for the modern data stack — Postgres as source, Airflow
orchestration, dbt transformations, Snowflake warehouse.

## Architecture

```
source_postgres ──(Airflow: extract to Parquet)──► ./data
      │                                               │
      │                                    (Airflow: PUT to stage + COPY INTO)
      ▼                                               ▼
  mimic data                                    Snowflake RAW
                                                      │
                                          (Airflow → DockerOperator → dbt)
                                                      ▼
                                          Snowflake STAGING / MARTS
```

### Containers (`docker compose`)

| Service | Purpose | Port |
| --- | --- | --- |
| `source_postgres` | Business/source database; mimic data lands here | `5433` |
| `postgres` | Airflow metadata database | — |
| `airflow-apiserver` | Airflow UI + REST API | `8080` |
| `airflow-scheduler` / `-dag-processor` / `-triggerer` | Airflow core (LocalExecutor) | — |
| `dbt` | Build-only image (`dbt-snowflake`); Airflow runs it via `DockerOperator` | — |

## Setup

1. Install Docker Desktop and make sure `docker` / `docker compose` are on your PATH.
2. Copy env and fill in Snowflake credentials:
   ```bash
   cp .env.example .env
   # set HOST_PROJECT_DIR to this repo's absolute path
   # set FERNET_KEY (command is in the file)
   # fill SNOWFLAKE_* and AIRFLOW_CONN_SNOWFLAKE_DEFAULT
   ```
3. Build and start:
   ```bash
   docker compose build
   docker compose up -d
   ```
4. Airflow UI: http://localhost:8080 (user/pass from `.env`, default `airflow`/`airflow`).

## Usage

- **Source DB**: `psql postgresql://source:source@localhost:5433/source`. Schema and
  seed/mimic data go in `postgres/init/` (runs once on first container start) or via
  a dedicated DAG later.
- **dbt manually**:
  ```bash
  docker compose run --rm dbt deps
  docker compose run --rm dbt run
  docker compose run --rm dbt test
  ```
- **Pipeline**: trigger the `postgres_to_snowflake` DAG in the Airflow UI. It is a
  skeleton — populate `TABLES` in `airflow/dags/postgres_to_snowflake.py` and the
  dbt models once the business domain is defined.

## Layout

```
airflow/
  Dockerfile, requirements.txt   custom Airflow image (providers: postgres, snowflake, docker)
  dags/postgres_to_snowflake.py  ELT skeleton
dbt/
  Dockerfile                     dbt-snowflake image
  dbt_project.yml, profiles.yml  profiles.yml reads SNOWFLAKE_* env vars
  models/staging, models/marts
postgres/init/                   SQL run on first source_postgres start
data/                            extract staging area (gitignored)
```

## Next steps

- [ ] Define the business domain + source schema (`postgres/init/`)
- [ ] Generate mimic data
- [ ] Fill in `TABLES` and COPY logic in the DAG
- [ ] Build staging + mart dbt models
