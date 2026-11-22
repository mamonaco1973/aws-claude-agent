#!/bin/bash
# ==============================================================================
# FILE: lib.sh
# ==============================================================================
# Helpers shared by apply.sh, validate.sh, run-now.sh and destroy.sh.
# Sourced, never run directly.
# ==============================================================================

# AWS_REGION outranks AWS_DEFAULT_REGION in the CLI, so pin both.
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

LOCK_FILE="03-agent/claude-lock.json"

# ------------------------------------------------------------------------------
# lock_id <file>
# ------------------------------------------------------------------------------
# Prints the Managed Agents ID that `ant apply` recorded for a resource
# file in 03-agent/ (environment.yaml, agent.md, deployment-nightly.md).
# Matches on the file name so the exact key format in the lock file
# doesn't matter. Prints nothing if the lock file or entry is missing.
# ------------------------------------------------------------------------------
lock_id() {
  [ -f "$LOCK_FILE" ] || return 0
  jq -r --arg f "$1" \
    '.resources | to_entries[] | select(.key | endswith($f)) | .value.id' \
    "$LOCK_FILE" | head -n 1
}

# ------------------------------------------------------------------------------
# ensure_venv
# ------------------------------------------------------------------------------
# A local virtualenv with the Anthropic SDK for run_now.py, created once.
# ------------------------------------------------------------------------------
ensure_venv() {
  if [ ! -x .venv/bin/python ]; then
    echo "NOTE: Creating .venv with the Anthropic SDK."
    python3 -m venv .venv
    .venv/bin/pip install -q --disable-pip-version-check \
      -r 02-worker/worker/requirements.txt
  fi
}
