"""Postgres -> files -> Snowflake stage -> COPY INTO -> dbt.

SKELETON. Fill in TABLES and the COPY/model details once the source schema is
defined. The flow:

    extract_to_files   PostgresHook reads each table, writes Parquet to /opt/airflow/data
    upload_to_stage    SnowflakeHook PUTs the files to an internal named stage
    copy_into_raw      COPY INTO RAW.<table> FROM @stage
    dbt_run / dbt_test DockerOperator runs the dbt project against Snowflake

Connections (defined via env vars in .env):
    source_postgres      -> AIRFLOW_CONN_SOURCE_POSTGRES
    snowflake_default    -> AIRFLOW_CONN_SNOWFLAKE_DEFAULT
"""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

import pendulum
from airflow.sdk import dag, task
from airflow.providers.docker.operators.docker import DockerOperator
from docker.types import Mount

SOURCE_CONN_ID = "source_postgres"
SNOWFLAKE_CONN_ID = "snowflake_default"
DATA_DIR = Path("/opt/airflow/data")

RAW_DATABASE = os.environ.get("SNOWFLAKE_DATABASE", "ANALYTICS_DB")
RAW_SCHEMA = os.environ.get("SNOWFLAKE_RAW_SCHEMA", "RAW")
SNOWFLAKE_STAGE = f"{RAW_DATABASE}.{RAW_SCHEMA}.AIRFLOW_STAGE"

# source table in Postgres (schema-qualified) -> raw table name in Snowflake
# (created under {RAW_DATABASE}.{RAW_SCHEMA})
TABLES: dict[str, str] = {
    # "app.customers": "CUSTOMERS",
}

DBT_IMAGE = "modern-data-stack/dbt:local"
HOST_PROJECT_DIR = os.environ.get("HOST_PROJECT_DIR", "")

# Snowflake creds forwarded to the dbt container (profiles.yml reads these).
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


@dag(
    dag_id="postgres_to_snowflake",
    schedule=None,  # trigger manually until the pipeline is fleshed out
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["elt", "snowflake", "dbt"],
)
def postgres_to_snowflake():
    @task
    def extract_to_files() -> list[str]:
        """Read each source table into a Parquet file under DATA_DIR."""
        from airflow.providers.postgres.hooks.postgres import PostgresHook

        if not TABLES:
            raise ValueError("TABLES is empty — define the source tables first.")

        DATA_DIR.mkdir(parents=True, exist_ok=True)
        hook = PostgresHook(postgres_conn_id=SOURCE_CONN_ID)
        engine = hook.get_sqlalchemy_engine()
        written: list[str] = []
        run_ts = datetime.utcnow().strftime("%Y%m%dT%H%M%S")

        import pandas as pd

        for source_table in TABLES:
            df = pd.read_sql(f"SELECT * FROM {source_table}", engine)
            safe = source_table.replace(".", "__")
            out = DATA_DIR / f"{safe}_{run_ts}.parquet"
            df.to_parquet(out, index=False)
            written.append(str(out))
        return written

    @task
    def upload_to_stage(files: list[str]) -> None:
        from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        hook.run(f"CREATE STAGE IF NOT EXISTS {SNOWFLAKE_STAGE}")
        for f in files:
            hook.run(
                f"PUT file://{f} @{SNOWFLAKE_STAGE} AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
            )

    @task
    def copy_into_raw() -> None:
        from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        for source_table, target_table in TABLES.items():
            pattern = source_table.replace(".", "__")
            hook.run(
                f"""
                COPY INTO {RAW_DATABASE}.{RAW_SCHEMA}.{target_table}
                FROM @{SNOWFLAKE_STAGE}
                PATTERN = '.*{pattern}.*\\.parquet'
                FILE_FORMAT = (TYPE = PARQUET)
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                """
            )

    dbt_run = DockerOperator(
        task_id="dbt_run",
        image=DBT_IMAGE,
        command="run",
        environment=_DBT_ENV,
        mounts=(
            [Mount(source=f"{HOST_PROJECT_DIR}/dbt", target="/usr/app", type="bind")]
            if HOST_PROJECT_DIR
            else []
        ),
        mount_tmp_dir=False,
        docker_url="unix://var/run/docker.sock",
        network_mode="bridge",
        auto_remove="success",
    )

    dbt_test = DockerOperator(
        task_id="dbt_test",
        image=DBT_IMAGE,
        command="test",
        environment=_DBT_ENV,
        mounts=(
            [Mount(source=f"{HOST_PROJECT_DIR}/dbt", target="/usr/app", type="bind")]
            if HOST_PROJECT_DIR
            else []
        ),
        mount_tmp_dir=False,
        docker_url="unix://var/run/docker.sock",
        network_mode="bridge",
        auto_remove="success",
    )

    files = extract_to_files()
    upload_to_stage(files) >> copy_into_raw() >> dbt_run >> dbt_test


postgres_to_snowflake()
