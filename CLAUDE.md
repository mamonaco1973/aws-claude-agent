# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What This Lab Does

A Claude Managed Agent on a **self-hosted environment**: the agent loop runs
at Anthropic, the tools run in an ECS Fargate worker in a private subnet that
connects outbound only. A scheduled deployment (06:00 UTC) runs a read-only
audit of a private RDS PostgreSQL database and writes a markdown report to
S3. See README.md for the full design, verified beta facts and costs.

## Commands

```bash
./apply.sh      # 01-rds -> ECR + image -> 02-worker -> environment ->
                #   key prompt (Console-only) -> agent + deployment -> validate
./run-now.sh    # fire the deployment now and stream the session (the demo)
./validate.sh   # workers_polling >= 1, run-now, newest report, no public IP,
                #   zero ingress rules
./destroy.sh    # archive deployment/agent/environment, delete sessions,
                #   empty S3 + ECR, destroy 02 then 01
./check_env.sh  # aws, terraform, docker, jq, ant, python3, envsubst,
                #   ANTHROPIC_API_KEY
```

Region is us-east-1 (pinned in `lib.sh` and `01-rds/main.tf`).

## Layout

```
01-rds/       Terraform: VPC, NAT, RDS (IAM auth), report bucket, seed loader
02-worker/    Terraform: ECR, environment secret, IAM, worker SG, ECS service
02-worker/worker/  image: Dockerfile, worker.py (EnvironmentWorker), psql-iam
03-agent/     ant apply files: environment.yaml, agent.md.tmpl,
              deployment-nightly.md; run_now.py (session streamer)
```

`03-agent/agent.md` (rendered) and `03-agent/claude-lock.json` (IDs from
`ant apply`) are generated and gitignored.

## Rules

- `ANTHROPIC_API_KEY` never goes on the worker. The worker gets only
  `ANTHROPIC_ENVIRONMENT_ID` / `ANTHROPIC_ENVIRONMENT_KEY` from Secrets
  Manager.
- The worker security group has no ingress rules and `assign_public_ip` is
  false; validate.sh fails if either changes.
- The task role keeps exactly `rds-db:connect` (agent_ro) and
  `s3:PutObject` (reports/*).
- Managed Agents is beta: check the live docs before changing SDK, `ant` or
  API usage.

## Code Commenting Standards

- Comment lines <= 80 characters.
- Shell: `set -euo pipefail`, a header block (FILE, purpose, high-level
  flow, notes) and section banners for each step; scripts are idempotent.
- Terraform: a banner per file and per logical resource group explaining
  *why* the infrastructure exists, not what the resource type says.
- Python: module docstring stating the purpose; inline comments explain
  intent only, never restate the code.
- Output from apply/validate/destroy uses `NOTE:` / `WARNING:` / `ERROR:`
  prefixes and stays readable at 93x26 (asciinema).
