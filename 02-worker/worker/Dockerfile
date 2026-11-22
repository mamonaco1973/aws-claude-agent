# ==============================================================================
# CLAUDE AGENT WORKER IMAGE
# ==============================================================================
# The agent's toolbox: /bin/bash (the SDK requires that exact path), psql,
# the AWS CLI, and the Python SDK's EnvironmentWorker. Runs as a non-root
# user in /workspace, which is where the agent's file tools are confined.
# ==============================================================================

FROM python:3.13-slim-trixie

# ------------------------------------------------------------------------------
# SYSTEM TOOLS
# ------------------------------------------------------------------------------
# postgresql-client from trixie is 17, matching the RDS major version.
# The RDS CA bundle lets psql verify the server (sslmode=verify-full).
# ------------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-client ca-certificates curl unzip jq less \
 && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
      -o /tmp/awscliv2.zip \
 && unzip -q /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install \
 && curl -fsSL \
      https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
      -o /etc/ssl/certs/rds-global-bundle.pem \
 && apt-get purge -y unzip \
 && rm -rf /tmp/aws /tmp/awscliv2.zip /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# WORKER
# ------------------------------------------------------------------------------
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY worker.py /app/worker.py
COPY psql-iam /usr/local/bin/psql-iam
RUN chmod 0755 /usr/local/bin/psql-iam

# ------------------------------------------------------------------------------
# NON-ROOT RUNTIME
# ------------------------------------------------------------------------------
RUN useradd --uid 10001 --create-home --shell /bin/bash worker \
 && mkdir /workspace \
 && chown worker:worker /workspace

USER worker
WORKDIR /workspace

ENV PYTHONUNBUFFERED=1 \
    PGSSLMODE=verify-full \
    PGSSLROOTCERT=/etc/ssl/certs/rds-global-bundle.pem

ENTRYPOINT ["python", "/app/worker.py"]
