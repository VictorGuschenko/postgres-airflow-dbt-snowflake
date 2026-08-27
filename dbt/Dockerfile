FROM python:3.11-slim

ENV PIP_NO_CACHE_DIR=1 \
    DBT_PROFILES_DIR=/usr/app \
    DBT_PROJECT_DIR=/usr/app

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "dbt-snowflake~=1.9"

WORKDIR /usr/app
COPY . /usr/app

# Pre-install dbt package dependencies if a packages.yml is present.
RUN dbt deps || true

ENTRYPOINT ["dbt"]
CMD ["--version"]
