#!/bin/bash
# ==============================================================================
# FILE: apply.sh
# ==============================================================================
# ORCHESTRATION SCRIPT: BUILD THE WHOLE LAB
# ==============================================================================
# Builds the private database, the outbound-only worker, and the scheduled
# agent, then runs the validation (which runs the agent once).
#
# High-level flow:
#   1) 01-rds:    VPC, NAT, private RDS with IAM auth, report bucket.
#   2) 02-worker: ECR first, then build and push the worker image.
#   3) 02-worker: Secrets Manager, IAM, security group, ECS service.
#   4) 03-agent:  create the self-hosted environment with `ant apply`.
#   5) Store the environment key (Console-only: pauses here once).
#   6) Roll the ECS service onto the image and the key.
#   7) 03-agent:  sync the agent and the nightly deployment.
#   8) Wait for the seed load, then run validate.sh.
#
# Notes:
# - Idempotent: re-running skips the key prompt when Secrets Manager
#   already holds a key for the current environment.
# - CLAUDE_MODEL overrides the agent's model (default claude-haiku-5-5).
# - ANTHROPIC_ENVIRONMENT_KEY, if set, is used instead of prompting.
# - ANTHROPIC_ENVIRONMENT_KEY_FILE, if set, is polled for the key instead
#   of prompting (for runs without a terminal).
# ==============================================================================

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

./check_env.sh

export CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-5-5}"
START=$(date +%s)
PAUSED=0

# ==============================================================================
# STEP 1: PHASE 01 - DATABASE, NETWORK, REPORT BUCKET
# ==============================================================================
echo "NOTE: Phase 01 - private database and report bucket."
terraform -chdir=01-rds init -input=false > /dev/null
terraform -chdir=01-rds apply -auto-approve -input=false

SEED_PARAM=$(terraform -chdir=01-rds output -raw seed_status_param)
BUCKET=$(terraform -chdir=01-rds output -raw reports_bucket)

# ==============================================================================
# STEP 2: PHASE 02 - REGISTRY, THEN THE IMAGE
# ==============================================================================
# The ECS service can't start without an image, so the repository is
# created on its own first and the image pushed before the full apply.
# ==============================================================================
echo "NOTE: Phase 02 - container registry and worker image."
terraform -chdir=02-worker init -input=false > /dev/null
terraform -chdir=02-worker apply -auto-approve -input=false \
  -target=aws_ecr_repository.worker

REPO=$(terraform -chdir=02-worker output -raw ecr_repository_url)
aws ecr get-login-password | \
  docker login --username AWS --password-stdin "${REPO%%/*}" > /dev/null
docker build --platform linux/amd64 -q -t "$REPO:latest" 02-worker/worker
docker push -q "$REPO:latest"

# ==============================================================================
# STEP 3: PHASE 02 - THE WORKER SERVICE
# ==============================================================================
echo "NOTE: Phase 02 - worker service, IAM and security group."
terraform -chdir=02-worker apply -auto-approve -input=false

SECRET_ARN=$(terraform -chdir=02-worker output -raw environment_secret_arn)
CLUSTER=$(terraform -chdir=02-worker output -raw cluster_name)
SERVICE=$(terraform -chdir=02-worker output -raw service_name)

# ==============================================================================
# STEP 4: PHASE 03 - THE SELF-HOSTED ENVIRONMENT
# ==============================================================================
echo "NOTE: Phase 03 - self-hosted Managed Agents environment."
(cd 03-agent && ant apply --yes environment.yaml)
ENV_ID=$(lock_id environment.yaml)
echo "NOTE: Environment ID is $ENV_ID."

# ==============================================================================
# STEP 5: THE ENVIRONMENT KEY
# ==============================================================================
# Environment keys can only be generated in the Console. If Secrets
# Manager already holds a key for this environment, there's nothing to do;
# otherwise take it from ANTHROPIC_ENVIRONMENT_KEY or prompt for it.
# ==============================================================================
STORED_ENV=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
  --query SecretString --output text 2>/dev/null | \
  jq -r '.environment_id // empty' 2>/dev/null || true)

if [ "$STORED_ENV" = "$ENV_ID" ] && [ -z "${ANTHROPIC_ENVIRONMENT_KEY:-}" ]
then
  echo "NOTE: Secrets Manager already holds the key for $ENV_ID."
else
  if [ -z "${ANTHROPIC_ENVIRONMENT_KEY:-}" ]; then
    echo "=================================================================="
    echo " ACTION NEEDED: generate the environment key (Console only)"
    echo "=================================================================="
    echo "  1. Open https://platform.claude.com/environments"
    echo "  2. Open 'claude-agent-aws-worker' ($ENV_ID)"
    echo "  3. Click 'Generate environment key' and copy it (sk-ant-oat01-)"
    echo "=================================================================="
    PAUSE_START=$(date +%s)
    if [ -n "${ANTHROPIC_ENVIRONMENT_KEY_FILE:-}" ]; then
      # Unattended runs (CI, a remote shell): wait up to 30 minutes for
      # someone to drop the key into this file.
      echo "NOTE: Waiting for the key in $ANTHROPIC_ENVIRONMENT_KEY_FILE."
      for _ in $(seq 1 180); do
        [ -s "$ANTHROPIC_ENVIRONMENT_KEY_FILE" ] && break
        sleep 10
      done
      ANTHROPIC_ENVIRONMENT_KEY=$(tr -d '[:space:]' \
        < "$ANTHROPIC_ENVIRONMENT_KEY_FILE" 2>/dev/null || true)
    elif [ -t 0 ]; then
      read -rsp "Paste the environment key: " ANTHROPIC_ENVIRONMENT_KEY
      echo
    else
      echo "ERROR: No terminal to prompt on. Re-run with:"
      echo "  ANTHROPIC_ENVIRONMENT_KEY=sk-ant-oat01-... ./apply.sh"
      exit 2
    fi
    PAUSED=$(( $(date +%s) - PAUSE_START ))
  fi

  case "$ANTHROPIC_ENVIRONMENT_KEY" in
    sk-ant-oat01-*) ;;
    *) echo "ERROR: That isn't an environment key (sk-ant-oat01-...)."
       exit 1 ;;
  esac

  # Piped through jq so the key never appears on a command line.
  jq -n --arg id "$ENV_ID" --arg key "$ANTHROPIC_ENVIRONMENT_KEY" \
    '{environment_id: $id, environment_key: $key}' | \
    aws secretsmanager put-secret-value --secret-id "$SECRET_ARN" \
      --secret-string file:///dev/stdin > /dev/null
  echo "NOTE: Environment key stored in Secrets Manager."
fi

# ==============================================================================
# STEP 6: ROLL THE WORKER
# ==============================================================================
# A fresh deployment picks up the newest image and the stored key.
# ==============================================================================
echo "NOTE: Rolling the ECS service and waiting for it to settle."
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --force-new-deployment > /dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
echo "NOTE: Worker service is stable."

# ==============================================================================
# STEP 7: PHASE 03 - THE AGENT AND ITS SCHEDULE
# ==============================================================================
echo "NOTE: Phase 03 - agent ($CLAUDE_MODEL) and nightly deployment."
envsubst '${CLAUDE_MODEL}' < 03-agent/agent.md.tmpl > 03-agent/agent.md
(cd 03-agent && ant apply --yes agent.md deployment-nightly.md)

# ==============================================================================
# STEP 8: WAIT FOR THE SEED LOAD
# ==============================================================================
# The loader host has been working since phase 01; usually it's done by
# now. It reports through an SSM parameter and then powers itself off.
# ==============================================================================
echo "NOTE: Waiting for the Pagila seed load to finish."
for _ in $(seq 1 80); do
  STATUS=$(aws ssm get-parameter --name "$SEED_PARAM" \
    --query Parameter.Value --output text)
  case "$STATUS" in
    done)    echo "NOTE: Seed load complete."; break ;;
    failed*) echo "ERROR: Seed load $STATUS (see /var/log/seed.log)."
             exit 1 ;;
    *)       sleep 15 ;;
  esac
done
if [ "$STATUS" != "done" ]; then
  echo "ERROR: Seed load did not finish in 20 minutes."
  exit 1
fi

ELAPSED=$(( $(date +%s) - START - PAUSED ))
echo "NOTE: Build complete in $((ELAPSED / 60))m $((ELAPSED % 60))s" \
     "(excluding ${PAUSED}s waiting for the key)."
echo "NOTE: Reports land in s3://$BUCKET/reports/."

# ==============================================================================
# STEP 9: VALIDATE (RUNS THE AGENT ONCE)
# ==============================================================================
./validate.sh
