ARG AIRFLOW_IMAGE_NAME=apache/airflow:3.3.1
FROM ${AIRFLOW_IMAGE_NAME}

# Providers + libraries needed by the DAGs.
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
