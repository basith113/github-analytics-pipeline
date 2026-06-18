FROM apache/airflow:2.8.0-python3.11

COPY docker/airflow/requirements.txt /tmp/github-pipeline-airflow-requirements.txt

RUN pip install --no-cache-dir -r /tmp/github-pipeline-airflow-requirements.txt

