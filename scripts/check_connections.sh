#!/usr/bin/env bash
# End-to-end connectivity check for the local stack.
# Run after `docker compose up -d` (wait until services are healthy).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Compose services"
docker compose ps

echo
echo "==> 1/5  Airflow -> metadata Postgres"
docker compose exec -T airflow-scheduler airflow db check

echo
echo "==> 2/5  Airflow -> source_postgres (AIRFLOW_CONN_SOURCE_POSTGRES)"
docker compose exec -T airflow-scheduler python - <<'PY'
from airflow.providers.postgres.hooks.postgres import PostgresHook
print("source_postgres:", PostgresHook(postgres_conn_id="source_postgres").get_first("select version()")[0][:40])
PY

echo
echo "==> 3/5  Airflow -> Snowflake (snowflake_default)"
docker compose exec -T airflow-scheduler python - <<'PY'
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
h = SnowflakeHook(snowflake_conn_id="snowflake_default")
print("snowflake:", h.get_first("select current_account(), current_warehouse(), current_role()"))
PY

echo
echo "==> 4/5  Airflow -> Docker daemon (DockerOperator prerequisite)"
docker compose exec -T airflow-scheduler python - <<'PY'
import docker
c = docker.from_env()
print("docker api:", c.version()["Version"], "images:", [t for i in c.images.list() for t in i.tags if "dbt" in t] or "(dbt image not built yet)")
PY

echo
echo "==> 5/5  dbt -> Snowflake (dbt debug)"
docker compose run --rm dbt debug

echo
echo "All checks passed."
