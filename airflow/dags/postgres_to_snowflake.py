"""Postgres -> files -> Snowflake stage -> COPY INTO -> dbt.

Flow:

    extract_to_files   PostgresHook reads each source table, writes Parquet to /opt/airflow/data
    upload_to_stage    SnowflakeHook PUTs the files to the internal named stage RAW.AIRFLOW_STAGE
    copy_into_raw      TRUNCATE + COPY INTO RAW.<table> FROM @stage/<file> (full snapshot, 1:1)
    dbt_run / dbt_test DockerOperator runs the dbt project against Snowflake

The stage, file format and RAW.* tables are declared in snowflake/raw_tables.sql
(run that once per environment before triggering the DAG).

Environment: DBT_TARGET (dev | prod, default dev) selects the physical Snowflake
database <SNOWFLAKE_DATABASE>_<TARGET> for both the RAW load here and the dbt
run/test tasks. dev and prod are fully separate databases.

Connections (defined via env vars in .env):
    source_postgres      -> AIRFLOW_CONN_SOURCE_POSTGRES
    snowflake_default    -> AIRFLOW_CONN_SNOWFLAKE_DEFAULT
"""

from __future__ import annotations

import os
from datetime import UTC, datetime
from pathlib import Path

import pendulum
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import dag, task
from docker.types import Mount

SOURCE_CONN_ID = "source_postgres"
SNOWFLAKE_CONN_ID = "snowflake_default"
DATA_DIR = Path("/opt/airflow/data")

# dev | prod — selects the isolated Snowflake database for the whole pipeline.
DBT_TARGET = os.environ.get("DBT_TARGET", "dev")
_DB_BASE = os.environ.get("SNOWFLAKE_DATABASE", "ANALYTICS_DB")
RAW_DATABASE = f"{_DB_BASE}_{DBT_TARGET.upper()}"
RAW_SCHEMA = os.environ.get("SNOWFLAKE_RAW_SCHEMA", "RAW")
SNOWFLAKE_STAGE = f"{RAW_DATABASE}.{RAW_SCHEMA}.AIRFLOW_STAGE"
PARQUET_FORMAT = f"{RAW_DATABASE}.{RAW_SCHEMA}.PARQUET_FORMAT"

# source table in Postgres (schema-qualified) -> raw table name in Snowflake,
# under {RAW_DATABASE}.{RAW_SCHEMA}. Load order does not matter (full snapshot,
# no FKs enforced in RAW).
TABLES: dict[str, str] = {
    "app.customers": "CUSTOMERS",
    "app.agents": "AGENTS",
    "app.products": "PRODUCTS",
    "app.policies": "POLICIES",
    "app.premium_payments": "PREMIUM_PAYMENTS",
    "app.claims": "CLAIMS",
    "app.claim_payments": "CLAIM_PAYMENTS",
}

DBT_IMAGE = "modern-data-stack/dbt:local"
HOST_PROJECT_DIR = os.environ.get("HOST_PROJECT_DIR", "")

# Snowflake creds + target forwarded to the dbt container (profiles.yml reads these).
_DBT_ENV = {
    k: os.environ[k]
    for k in (
        "SNOWFLAKE_ACCOUNT",
        "SNOWFLAKE_USER",
        "SNOWFLAKE_PASSWORD",
        "SNOWFLAKE_ROLE",
        "SNOWFLAKE_DATABASE",
        "SNOWFLAKE_WAREHOUSE",
        "SNOWFLAKE_SCHEMA",
        "SNOWFLAKE_THREADS",
    )
    if k in os.environ
}
_DBT_ENV["DBT_TARGET"] = DBT_TARGET

_DBT_MOUNTS = (
    [Mount(source=f"{HOST_PROJECT_DIR}/dbt", target="/usr/app", type="bind")]
    if HOST_PROJECT_DIR
    else []
)


@dag(
    dag_id="postgres_to_snowflake",
    schedule=None,  # trigger manually
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["elt", "snowflake", "dbt"],
)
def postgres_to_snowflake():
    @task
    def extract_to_files() -> dict[str, str]:
        """Read each source table into a Parquet file. Returns {TARGET: filename}."""
        import pandas as pd
        from airflow.providers.postgres.hooks.postgres import PostgresHook

        if not TABLES:
            raise ValueError("TABLES is empty — define the source tables first.")

        DATA_DIR.mkdir(parents=True, exist_ok=True)
        engine = PostgresHook(postgres_conn_id=SOURCE_CONN_ID).get_sqlalchemy_engine()
        run_ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")

        manifest: dict[str, str] = {}
        for source_table, target in TABLES.items():
            # NUMERIC columns arrive as Python Decimal (object dtype); pyarrow
            # writes them as decimal128, so exact values are preserved. Do NOT
            # coerce these columns to float.
            df = pd.read_sql(f"SELECT * FROM {source_table}", engine)
            fname = f"{target}_{run_ts}.parquet"
            df.to_parquet(DATA_DIR / fname, index=False)
            manifest[target] = fname
            print(f"{source_table}: {len(df)} rows -> {fname}")
        return manifest

    @task
    def upload_to_stage(manifest: dict[str, str]) -> dict[str, str]:
        from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        for fname in manifest.values():
            # Parquet is already compressed; AUTO_COMPRESS=FALSE keeps the name
            # stable so COPY can address the file directly.
            hook.run(
                f"PUT file://{DATA_DIR / fname} @{SNOWFLAKE_STAGE} "
                f"AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
            )
        return manifest

    @task
    def copy_into_raw(manifest: dict[str, str]) -> None:
        from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        for target, fname in manifest.items():
            fqtn = f"{RAW_DATABASE}.{RAW_SCHEMA}.{target}"
            hook.run(f"TRUNCATE TABLE {fqtn}")
            hook.run(
                f"""
                COPY INTO {fqtn}
                FROM @{SNOWFLAKE_STAGE}/{fname}
                FILE_FORMAT = (FORMAT_NAME = {PARQUET_FORMAT})
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                ON_ERROR = ABORT_STATEMENT
                """
            )

    dbt_run = DockerOperator(
        task_id="dbt_run",
        image=DBT_IMAGE,
        command=f"run --target {DBT_TARGET}",
        environment=_DBT_ENV,
        mounts=_DBT_MOUNTS,
        mount_tmp_dir=False,
        docker_url="unix://var/run/docker.sock",
        network_mode="bridge",
        auto_remove="success",
    )

    dbt_test = DockerOperator(
        task_id="dbt_test",
        image=DBT_IMAGE,
        command=f"test --target {DBT_TARGET}",
        environment=_DBT_ENV,
        mounts=_DBT_MOUNTS,
        mount_tmp_dir=False,
        docker_url="unix://var/run/docker.sock",
        network_mode="bridge",
        auto_remove="success",
    )

    manifest = extract_to_files()
    copy_into_raw(upload_to_stage(manifest)) >> dbt_run >> dbt_test


postgres_to_snowflake()
