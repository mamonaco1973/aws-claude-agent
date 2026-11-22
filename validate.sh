#!/bin/bash
# ==============================================================================
# FILE: validate.sh
# ==============================================================================
# Proves the lab works end to end and that nothing is exposed.
#
# High-level flow:
#   1) The work queue reports at least one worker polling (asked from this
#      machine with the API key, never from the worker).
#   2) run-now.sh runs one audit session to completion.
#   3) The newest report is in S3; print its title and headline.
#   4) The worker task has no public IP and its security group has zero
#      ingress rules.
# ==============================================================================

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

ENV_ID=$(lock_id environment.yaml)
BUCKET=$(terraform -chdir=01-rds output -raw reports_bucket)
CLUSTER=$(terraform -chdir=02-worker output -raw cluster_name)
SERVICE=$(terraform -chdir=02-worker output -raw service_name)
WORKER_SG=$(terraform -chdir=02-worker output -raw worker_sg_id)

# ==============================================================================
# CHECK 1: A WORKER IS POLLING
# ==============================================================================
echo "NOTE: Checking the work queue for $ENV_ID."
POLLING=0
for _ in $(seq 1 18); do
  POLLING=$(ant beta:environments:work stats --environment-id "$ENV_ID" \
    --transform workers_polling -r)
  [ "${POLLING:-0}" -ge 1 ] && break
  sleep 10
done
ant beta:environments:work stats --environment-id "$ENV_ID" \
  --transform '{workers_polling,depth,pending}' --format json
if [ "${POLLING:-0}" -lt 1 ]; then
  echo "ERROR: No worker is polling the environment."
  exit 1
fi
echo "NOTE: $POLLING worker(s) polling."

# ==============================================================================
# CHECK 2: ONE AUDIT, START TO FINISH
# ==============================================================================
echo "NOTE: Running the audit now."
./run-now.sh

# ==============================================================================
# CHECK 3: THE REPORT IS IN S3
# ==============================================================================
KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix reports/ \
  --query 'sort_by(Contents, &LastModified)[-1].Key' --output text)
if [ -z "$KEY" ] || [ "$KEY" = "None" ]; then
  echo "ERROR: No report found under s3://$BUCKET/reports/."
  exit 1
fi
echo "NOTE: Newest report is s3://$BUCKET/$KEY"
echo "------------------------------------------------------------------"
aws s3 cp "s3://$BUCKET/$KEY" - | \
  awk '/^# /{print; next} /^## Headline/{h=1; print; next}
       /^## /{h=0} h && NF {print}' | cut -c1-90
echo "------------------------------------------------------------------"

# ==============================================================================
# CHECK 4: NOTHING EXPOSED
# ==============================================================================
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)
ENI=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)
read -r PRIVATE_IP PUBLIC_IP < <(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI" \
  --query 'NetworkInterfaces[0].[PrivateIpAddress, Association.PublicIp]' \
  --output text)
INGRESS=$(aws ec2 describe-security-groups --group-ids "$WORKER_SG" \
  --query 'length(SecurityGroups[0].IpPermissions)' --output text)

echo "NOTE: Worker ENI $ENI"
echo "NOTE:   private IP: $PRIVATE_IP"
echo "NOTE:   public IP:  $PUBLIC_IP"
echo "NOTE: Worker security group $WORKER_SG"
echo "NOTE:   ingress rules: $INGRESS"
aws ec2 describe-security-groups --group-ids "$WORKER_SG" \
  --query 'SecurityGroups[0].IpPermissionsEgress[].[IpProtocol, ToPort,
           join(`,`, [IpRanges[].CidrIp, UserIdGroupPairs[].GroupId][])]' \
  --output text | awk '{printf "NOTE:   egress: %s %s -> %s\n", $1, $2, $3}'

if [ "$PUBLIC_IP" != "None" ] || [ "$INGRESS" != "0" ]; then
  echo "ERROR: The worker is exposed."
  exit 1
fi
echo "NOTE: No public IP, no ingress. Validation passed."
