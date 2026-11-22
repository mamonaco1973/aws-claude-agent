#!/bin/bash
# ==============================================================================
# FILE: destroy.sh
# ==============================================================================
# ORCHESTRATION SCRIPT: TEAR DOWN IN REVERSE ORDER
# ==============================================================================
# High-level flow:
#   1) Anthropic side: archive the deployment (stops the schedule), delete
#      this agent's sessions, archive the agent and the environment.
#   2) Empty the report bucket (every version) and the ECR repository.
#   3) terraform destroy 02-worker, then 01-rds.
#
# Notes:
# - 03-agent has no Terraform; its resources live at Anthropic and are
#   removed in step 1.
# - Archived agents, environments and deployments stay listed (read-only)
#   in the Console; the API has no hard delete for them in this flow.
# - Safe to re-run: every step skips what is already gone.
# ==============================================================================

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

# ==============================================================================
# STEP 1: ANTHROPIC SIDE
# ==============================================================================
DEPLOYMENT_ID=$(lock_id deployment-nightly.md)
AGENT_ID=$(lock_id agent.md)
ENV_ID=$(lock_id environment.yaml)

if [ -n "$DEPLOYMENT_ID" ]; then
  echo "NOTE: Archiving deployment $DEPLOYMENT_ID (stops the schedule)."
  ant beta:deployments archive --deployment-id "$DEPLOYMENT_ID" \
    > /dev/null 2>&1 || echo "WARNING: already archived or not found."
fi

if [ -n "$AGENT_ID" ]; then
  echo "NOTE: Deleting this agent's sessions."
  for SID in $(ant beta:sessions list --agent-id "$AGENT_ID" \
                 --include-archived --transform id -r); do
    ant beta:sessions delete --session-id "$SID" > /dev/null 2>&1 \
      && echo "NOTE:   deleted $SID" \
      || echo "WARNING: could not delete $SID"
  done

  echo "NOTE: Archiving agent $AGENT_ID."
  ant beta:agents archive --agent-id "$AGENT_ID" > /dev/null 2>&1 \
    || echo "WARNING: already archived or not found."
fi

if [ -n "$ENV_ID" ]; then
  echo "NOTE: Archiving environment $ENV_ID."
  ant beta:environments archive --environment-id "$ENV_ID" \
    > /dev/null 2>&1 || echo "WARNING: already archived or not found."
fi

rm -f "$LOCK_FILE" 03-agent/agent.md

# ==============================================================================
# STEP 2: EMPTY THE BUCKET AND THE REGISTRY
# ==============================================================================
BUCKET=$(terraform -chdir=01-rds output -raw reports_bucket 2>/dev/null || true)
if [ -n "$BUCKET" ] && aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null
then
  echo "NOTE: Emptying s3://$BUCKET (all versions)."
  while true; do
    BATCH=$(aws s3api list-object-versions --bucket "$BUCKET" \
      --max-items 500 --output json \
      --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key,
               VersionId: VersionId}}')
    [ "$(echo "$BATCH" | jq '.Objects | length')" -eq 0 ] && break
    aws s3api delete-objects --bucket "$BUCKET" --delete "$BATCH" > /dev/null
  done
fi

REPO=$(terraform -chdir=02-worker output -raw ecr_repository_name \
  2>/dev/null || true)
if [ -n "$REPO" ]; then
  IMAGES=$(aws ecr list-images --repository-name "$REPO" \
    --query 'imageIds' --output json 2>/dev/null || echo "[]")
  if [ "$(echo "$IMAGES" | jq length)" -gt 0 ]; then
    echo "NOTE: Deleting images from ECR repository $REPO."
    aws ecr batch-delete-image --repository-name "$REPO" \
      --image-ids "$IMAGES" > /dev/null
  fi
fi

# ==============================================================================
# STEP 3: TERRAFORM, REVERSE ORDER
# ==============================================================================
echo "NOTE: Destroying phase 02 - worker."
terraform -chdir=02-worker init -input=false > /dev/null
terraform -chdir=02-worker destroy -auto-approve -input=false

echo "NOTE: Destroying phase 01 - database and network."
terraform -chdir=01-rds init -input=false > /dev/null
terraform -chdir=01-rds destroy -auto-approve -input=false

# ==============================================================================
# WHAT REMAINS AT ANTHROPIC
# ==============================================================================
echo "NOTE: Teardown complete. Left on the Anthropic side, by design:"
echo "NOTE:   the archived agent, environment and deployment (read-only,"
echo "NOTE:   no cost) and any deployment run records."
