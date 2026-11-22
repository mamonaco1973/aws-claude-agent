---
# ==============================================================================
# SCHEDULED DEPLOYMENT: THE NIGHTLY RUN
# ==============================================================================
# Anthropic's scheduler fires a new session at 06:00 UTC every day (UTC
# avoids DST skips and double runs; start times are jittered by up to a few
# minutes). Each session is capped at $5 of list cost, a hard stop for an
# unattended job. run-now.sh fires the same deployment on demand.
# The Markdown body below is the message that starts every run.
# ==============================================================================
name: claude-agent-nightly-audit
agent: ./agent.md
environment_id: ./environment.yaml
schedule:
  type: cron
  expression: "0 6 * * *"
  timezone: UTC
budget:
  type: limit
  max_list_cost: {amount: "500", currency: USD}
---

Run tonight's database audit, upload the report, and stop.
