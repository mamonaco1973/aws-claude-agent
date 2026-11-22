#!/bin/bash
# ==============================================================================
# FILE: run-now.sh
# ==============================================================================
# Fires the nightly deployment immediately and streams the session to this
# terminal: the agent's messages, each bash command it runs inside the
# VPC, and a few lines of each result. Exits when the agent finishes.
#
# This is the demo. The 06:00 UTC schedule fires the very same session.
# ==============================================================================

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

DEPLOYMENT_ID=$(lock_id deployment-nightly.md)
if [ -z "$DEPLOYMENT_ID" ]; then
  echo "ERROR: No deployment in $LOCK_FILE. Run ./apply.sh first."
  exit 1
fi

ensure_venv
.venv/bin/python 03-agent/run_now.py "$DEPLOYMENT_ID"
