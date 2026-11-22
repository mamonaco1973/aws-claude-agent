#!/bin/bash
# ==============================================================================
# FILE: check_env.sh
# ==============================================================================
# ENVIRONMENT VALIDATION SCRIPT
# ==============================================================================
# Confirms the build server has every tool and credential the lab needs
# before anything is created.
#
# High-level flow:
#   1) Verify required commands exist in PATH.
#   2) Verify ANTHROPIC_API_KEY is set (control-plane calls only).
#   3) Verify AWS credentials with STS and that Docker is running.
#
# Notes:
# - ANTHROPIC_API_KEY stays on this machine. The worker in AWS only ever
#   gets the narrower environment key.
# ==============================================================================

set -euo pipefail

echo "NOTE: Validating that required commands are found in your PATH."

# ------------------------------------------------------------------------------
# REQUIRED COMMANDS
# ------------------------------------------------------------------------------
# ant drives the Managed Agents control plane (ant apply, deployments,
# work-queue stats); python3 runs the session streamer in run-now.sh;
# envsubst renders the agent template.
# ------------------------------------------------------------------------------

commands=("aws" "terraform" "docker" "jq" "ant" "python3" "envsubst")
all_found=true

for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is not found in the current PATH."
    all_found=false
  else
    echo "NOTE: $cmd is found in the current PATH."
  fi
done

if [ "$all_found" = true ]; then
  echo "NOTE: All required commands are available."
else
  echo "ERROR: One or more required commands are missing."
  echo "ERROR: Install ant from github.com/anthropics/anthropic-cli/releases."
  exit 1
fi

# ------------------------------------------------------------------------------
# ANTHROPIC API KEY
# ------------------------------------------------------------------------------

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: ANTHROPIC_API_KEY is not set."
  echo "ERROR: Export a Claude API key for the control-plane calls."
  exit 1
fi
echo "NOTE: ANTHROPIC_API_KEY is set (used on this machine only)."

# ------------------------------------------------------------------------------
# AWS AND DOCKER
# ------------------------------------------------------------------------------

echo "NOTE: Checking AWS CLI connection."
if ! aws sts get-caller-identity --query Account --output text > /dev/null
then
  echo "ERROR: Failed to connect to AWS."
  echo "ERROR: Check credentials and environment variables."
  exit 1
fi
echo "NOTE: Successfully authenticated to AWS."

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not reachable."
  exit 1
fi
echo "NOTE: Docker is running."
