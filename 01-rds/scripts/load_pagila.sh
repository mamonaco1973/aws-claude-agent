#!/bin/bash
# ==============================================================================
# FILE: load_pagila.sh (EC2 user_data, rendered by Terraform)
# ==============================================================================
# One-shot seed loader for the private database.
#
# High-level flow:
#   1) Install the PostgreSQL client.
#   2) Read the master credentials from Secrets Manager (never user_data).
#   3) Pull the SQL files from the S3 seed/ prefix and load Pagila.
#   4) Create the agent's read-only IAM role and plant the audit findings.
#   5) Run a slow query workload so pg_stat_statements has something to say.
#   6) Record the result in SSM Parameter Store and power off.
#
# Notes:
# - apply.sh waits on the SSM parameter, not on this instance's state.
# - Output is in /var/log/seed.log (reach it with SSM Session Manager).
# ==============================================================================

set -euo pipefail
exec > >(tee -a /var/log/seed.log) 2>&1

REGION="${region}"
STATUS_PARAM="${status_param}"

# ------------------------------------------------------------------------------
# REPORT FAILURE, THEN STOP
# ------------------------------------------------------------------------------
# A failed load still powers off (no idle cost) but leaves the reason where
# apply.sh can print it.
# ------------------------------------------------------------------------------
fail() {
  aws ssm put-parameter --region "$REGION" --name "$STATUS_PARAM" \
    --type String --overwrite --value "failed at line $1" || true
  shutdown -h now
}
trap 'fail $LINENO' ERR

# ------------------------------------------------------------------------------
# POSTGRESQL CLIENT
# ------------------------------------------------------------------------------
dnf install -y jq
dnf install -y postgresql17 || dnf install -y postgresql16

# ------------------------------------------------------------------------------
# CREDENTIALS AND CONNECTION
# ------------------------------------------------------------------------------
SECRET=$(aws secretsmanager get-secret-value --region "$REGION" \
  --secret-id "${secret_arn}" --query SecretString --output text)

export PGHOST=$(echo "$SECRET" | jq -r .endpoint)
export PGUSER=$(echo "$SECRET" | jq -r .user)
export PGPASSWORD=$(echo "$SECRET" | jq -r .password)
export PGSSLMODE=require

# ------------------------------------------------------------------------------
# LOAD PAGILA
# ------------------------------------------------------------------------------
mkdir -p /tmp/seed
aws s3 cp --region "$REGION" --recursive "s3://${bucket}/seed/" /tmp/seed/
cd /tmp/seed

echo "NOTE: Loading Pagila into $PGHOST."
psql -d postgres -f pagila-db.sql
psql -d pagila -q -f pagila-schema.sql
psql -d pagila -q -f pagila-data.sql

echo "NOTE: Creating ${agent_db_user} and planting audit findings."
psql -d pagila -v agent_user="${agent_db_user}" -f seed-extras.sql

# ------------------------------------------------------------------------------
# SLOW QUERY WORKLOAD
# ------------------------------------------------------------------------------
# Leading-wildcard ILIKE and lower() defeat every index, so these show up at
# the top of pg_stat_statements by total time.
# ------------------------------------------------------------------------------
for i in $(seq 1 25); do
  psql -d pagila -q -o /dev/null -c "
    SELECT f.title, count(*)
      FROM rental r
      JOIN inventory i USING (inventory_id)
      JOIN film f USING (film_id)
     WHERE f.description ILIKE '%drama%'
     GROUP BY f.title ORDER BY 2 DESC;"
  psql -d pagila -q -o /dev/null -c "
    SELECT c.customer_id, sum(p.amount)
      FROM customer c
      JOIN payment p USING (customer_id)
     WHERE lower(c.email) LIKE '%sakila%'
     GROUP BY 1;"
done

# ------------------------------------------------------------------------------
# DONE
# ------------------------------------------------------------------------------
aws ssm put-parameter --region "$REGION" --name "$STATUS_PARAM" \
  --type String --overwrite --value "done"
echo "NOTE: Seed load complete, powering off."
shutdown -h now
