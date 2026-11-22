# A Claude Agent Inside Your VPC: Nightly Database Audit with Self-Hosted Managed Agents

An AI agent working inside your private network, every night, with nothing
exposed.

This lab runs a **Claude Managed Agent** whose agent loop runs at Anthropic
but whose **tools run inside your AWS account**, on a **self-hosted
environment**. A Fargate worker in a private subnet opens an outbound HTTPS
long-poll to Anthropic's work queue and executes the agent's bash and file
tool calls locally. Nothing connects in: there is no load balancer, no
public IP and no inbound security group rule.

Every night at 06:00 UTC, a **scheduled deployment** starts a session that
audits a private **RDS for PostgreSQL** database (the Pagila sample, with a
few problems planted in it) and writes a markdown report to S3. The agent
logs in with an **IAM auth token**, so no database password ever reaches the
container, and its IAM role can do exactly two things: connect as a
read-only database user, and put objects under `reports/`.

| Piece | Where | Role |
|---|---|---|
| **Agent loop + schedule** | Anthropic | `claude-haiku-5-5` by default, no web tools, cron `0 6 * * *` UTC, $5 cap per run |
| **Work queue** | Anthropic | the self-hosted environment; hands out sessions to whoever polls |
| **Fargate worker** | private subnets | `claude-agent-worker`: Python SDK `EnvironmentWorker`, bash, psql 17, AWS CLI; non-root, `/workspace` |
| **NAT gateway** | public subnet | the worker's only route out (443 to Anthropic and AWS APIs) |
| **RDS PostgreSQL 17** | private subnets | `claude-agent-postgres`, `db.t4g.micro`, single-AZ, IAM auth, Pagila loaded |
| **Seed loader** | private subnet | Amazon Linux `t3.micro`; loads Pagila once, then powers off |
| **S3 report bucket** | regional | `claude-agent-reports-<hex>`: private, versioned, SSE-S3; `reports/` and `seed/` |
| **Secrets Manager** | regional | `claude-agent-environment` (environment ID and key) and `claude-agent-postgres-credentials` (loader only) |
| **Build server** | your machine | Terraform, Docker, the `ant` CLI and `ANTHROPIC_API_KEY`; the only place that key lives |

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="architecture-dark.svg">
  <img alt="A Fargate worker in a private subnet of your VPC opens an outbound HTTPS long-poll through the NAT gateway to the Managed Agents work queue at Anthropic, where the agent loop and its 06:00 UTC schedule run; the build server drives that control plane with an API key. At start ECS pulls the worker image from ECR and injects the environment key from Secrets Manager, both from inside the task; the worker writes logs to CloudWatch. The agent's tool calls run in the worker: psql to a private RDS PostgreSQL 17 database on port 5432 with an IAM auth token, and s3:PutObject of the report to an S3 bucket. A seed loader host, run once, downloads the Pagila data from S3 and loads it into the database. No arrow enters the VPC." src="architecture-light.svg">
</picture>

Every arrow points from the side that opens the connection, and every arrow
that touches the VPC points out of it. Regenerate with
`python3 make_diagram.py`.

- **`01-rds/`** (Terraform) builds the VPC (`10.0.0.0/16`, two public and
  two private subnets in us-east-1a/b), one NAT gateway, an S3 gateway
  endpoint, RDS with a parameter group that preloads `pg_stat_statements`,
  the report bucket, and the seed loader.
- **`01-rds/data/`** holds the Pagila SQL and `seed-extras.sql`, which
  creates the agent's database role and plants the findings listed below.
- **`02-worker/`** (Terraform) builds ECR, the environment secret, the two
  IAM roles, the outbound-only security group, the log group and the ECS
  service. **`02-worker/worker/`** is the image: `Dockerfile`, `worker.py`
  and `psql-iam`.
- **`03-agent/`** (no Terraform) holds the Managed Agents resources as files
  synced with `ant apply`: `environment.yaml`, `agent.md.tmpl` (rendered to
  `agent.md` with the model filled in) and `deployment-nightly.md`.
  `run_now.py` is the session streamer behind `run-now.sh`.

## How a nightly run works

1. At 06:00 UTC (plus a few minutes of scheduler jitter), Anthropic fires
   the deployment: it creates a session for the agent on the self-hosted
   environment and sends the kickoff message ("Run tonight's database
   audit...").
2. The session becomes a **work item** on the environment's queue.
3. The worker's long-poll, already open, returns the work item. The worker
   claims it with its **environment key**.
4. Claude, running at Anthropic, decides on a tool call, for example
   `bash: psql-iam -c "SELECT ... FROM pg_stat_statements ..."`. The worker
   runs it in the container and posts the result back over the same
   outbound connection.
5. `psql-iam` asks the AWS CLI for a 15-minute IAM auth token (signed with
   the task role's credentials, no network call), and psql connects to RDS
   over TLS (`verify-full` against the RDS CA bundle) as `agent_ro`.
6. When the audit is done, the agent writes `/workspace/report.md` and runs
   `aws s3 cp ... s3://<bucket>/reports/YYYY-MM-DD.md`, then stops. The
   session goes idle; nothing is waiting on a human.

## Why outbound-only matters

A tool server that Claude calls **into** needs a public endpoint, TLS, an
authorization server, and an ingress rule that the whole internet can
reach, even if it then rejects most of it. Every one of those is attack
surface and every one is something you maintain.

A self-hosted worker inverts the connection. It **dials out** to a fixed
destination on 443 and asks for work, exactly like a CI runner or an SSM
agent. That means:

- **Nothing to scan or attack.** The worker has no public IP and its
  security group has zero ingress rules. `validate.sh` prints both.
- **It fits networks that forbid inbound.** Private subnets, a NAT or
  egress proxy, and no exceptions in the firewall change process.
- **Your data plane stays yours.** The database, the IAM role, the TLS
  session and the S3 write all happen inside your account with your
  controls and your CloudTrail.
- **The credential is narrow.** The worker holds an environment key that
  can only pull work for one environment. It cannot create agents, start
  sessions or call the Messages API. The organization's API key stays on
  the build server.

What "nothing exposed" does **not** mean: the agent's tool inputs and
outputs go to Anthropic so the model can read them. If the agent runs
`SELECT email FROM customer LIMIT 5`, those five emails leave your network
in the tool result. Use a database role and a system prompt that only see
what you would be comfortable sending, which is why the agent here gets
`pg_read_all_data` on a sample database and nothing in production.

## How this differs from an MCP sandbox (aws-lambda-microvms)

| | MCP sandbox (`aws-lambda-microvms`) | Self-hosted Managed Agent (this lab) |
|---|---|---|
| Who starts the connection | Claude calls **into** your API Gateway | your worker calls **out** to Anthropic |
| Exposed surface | public HTTPS endpoint, OAuth (Cognito), API Gateway | none; no listener at all |
| Who drives the work | a person chatting in Claude, turn by turn | a schedule; nobody is watching |
| Agent loop | the Claude app's | Managed Agents, at Anthropic |
| Tools | the ones you write and publish over MCP | the built-in agent toolset (bash, read, write, edit, glob, grep) running in your container, plus anything installed in the image |
| Identity at your resources | whatever your MCP server holds | the ECS task role (`rds-db:connect`, `s3:PutObject`) |
| Best for | interactive work in a shared sandbox | unattended jobs next to private data |

## Verified facts (Managed Agents is in beta)

Checked on 2026-11-22 against the live documentation and the published SDK
wheels. Re-check before relying on them.

- **Environment key.** Generated **only in the Console**: open the
  environment at <https://platform.claude.com/environments> and click
  **Generate environment key** (`sk-ant-oat01-...`). There is no API for
  it, even for an environment created through the API. This is why
  `apply.sh` pauses once.
- **SDK.** `anthropic.lib.environments.EnvironmentWorker` first ships in
  Python `anthropic` **0.103.0** (0.102.0 does not have it). The worker
  pins **2.12.0**. `.run()` polls until its task is cancelled; it installs
  no signal handlers, so `worker.py` wires SIGTERM to cancellation, and the
  docs ask for at least 30 s before a hard kill (ECS `stopTimeout` is 60).
- **Scheduled deployments.** `POST /v1/deployments` (SDK
  `client.beta.deployments`, CLI `ant beta:deployments`) with a cron
  `schedule`, an IANA timezone and the events that start each run. Each
  firing writes a deployment run record; `/run` fires one immediately,
  even while paused; `/pause`, `/unpause` and `/archive` manage the
  schedule. Self-hosted environments are supported. Firing is jittered by
  up to 15% of the interval, capped at 9 minutes.
- **`ant` CLI.** `ant apply` (1.30.0 or later) syncs the files in
  `03-agent/`; tested with 2.12.1.

### The other path: Claude Platform on AWS

Claude Platform on AWS (Anthropic-operated, billed through AWS Marketplace,
same API) also supports self-hosted environments, and there the worker
authenticates with **IAM SigV4** instead of an environment key: attach the
`AnthropicSelfHostedEnvironmentAccess` managed policy to the task role,
construct the client with `AnthropicAWS()` (with `AWS_REGION` and
`ANTHROPIC_AWS_WORKSPACE_ID`), and drop the secret and the Console pause
entirely. Console-generated environment keys don't work against that
endpoint, and `ant` reaches it by setting the AWS workspace variables
(version 1.42.0 or later).

It is the simpler worker, but it needs a Claude Platform on AWS
subscription and workspace, and every control-plane call (including
`ant apply`) then goes through the AWS endpoint. **This lab builds the
standard Anthropic API path.**

## Prerequisites

- AWS credentials with admin rights in the target account; us-east-1.
- Terraform 1.5+, Docker, `jq`, `envsubst` (gettext), Python 3.10+.
- The `ant` CLI from
  [anthropics/anthropic-cli releases](https://github.com/anthropics/anthropic-cli/releases)
  on your `PATH`.
- `ANTHROPIC_API_KEY` exported in your shell. It is used only on this
  machine, for control-plane calls (`ant apply`, firing the deployment,
  work-queue stats, streaming the session). It is never sent to AWS.

## Deploy

```bash
export ANTHROPIC_API_KEY=sk-ant-api03-...
./apply.sh
```

`apply.sh` runs `check_env.sh`, then builds phase 01, the ECR repository,
the image, the rest of phase 02, and the self-hosted environment. Then it
stops once:

```
==================================================================
 ACTION NEEDED: generate the environment key (Console only)
==================================================================
  1. Open https://platform.claude.com/environments
  2. Open 'claude-agent-aws-worker' (env_...)
  3. Click 'Generate environment key' and copy it (sk-ant-oat01-)
==================================================================
Paste the environment key:
```

The key goes straight into Secrets Manager (piped through `jq`, never on a
command line or in Terraform state). To skip the prompt, export
`ANTHROPIC_ENVIRONMENT_KEY` before running. Without a terminal (CI, a
remote shell), set `ANTHROPIC_ENVIRONMENT_KEY_FILE` to a path and
`apply.sh` waits up to 30 minutes for the key to appear there. On a re-run, the prompt is skipped
when Secrets Manager already holds a key for the current environment.

Then it rolls the ECS service, syncs the agent and the nightly deployment,
waits for the seed load, and runs `validate.sh`.

**Model.** The default is `claude-haiku-5-5`, the cheapest current model:
a run costs cents, and the mechanics (psql, markdown, `aws s3 cp`) are well
within its range. For a deeper report (better explanations of slow
queries, sharper business observations), pick a larger model:

```bash
CLAUDE_MODEL=claude-sonnet-5-5 ./apply.sh   # $2 / $10 per million tokens
CLAUDE_MODEL=claude-opus-5-5 ./apply.sh     # $4 / $20 per million tokens
```

Re-running `apply.sh` with a new model creates a new agent version and
moves the deployment to it.
Measured build time: **TBD** (excluding the time spent at the key prompt),
plus about **TBD** for the validation run.

## Run it now

```bash
./run-now.sh
```

This fires the nightly deployment immediately (a manual run creates
exactly the session the schedule would) and streams the session: the
agent's messages, each bash command it runs inside the VPC, and the first
lines of each result. It exits when the agent finishes. To watch a session
in the Console instead, `ant beta:sessions connect <session-id>` attaches
a terminal view.

## Validate

```bash
./validate.sh
```

1. Asks the work queue, from the build server, how many workers are
   polling (`ant beta:environments:work stats`); needs at least 1.
2. Runs `run-now.sh` to completion.
3. Finds the newest object under `reports/` and prints its title and
   headline bullets.
4. Looks up the running task's network interface and prints its private IP
   and its public IP (`None`), then the worker security group's ingress
   rule count (`0`) and its two egress rules.

## What the agent should find

`seed-extras.sql` plants these so you can grade the report:

| Finding | Planted as |
|---|---|
| Duplicate index | `idx_customer_last_name_dup` duplicates `idx_last_name` on `customer(last_name)` |
| Duplicate indexes (Pagila's own) | `idx_fk_payment_p2022_0N_customer_id` and `payment_p2022_0N_customer_id_idx` on every payment partition |
| Unused index | `idx_rental_return_date` |
| Slow queries | 25 runs each of a leading-wildcard `ILIKE` on `film.description` and a `lower(email) LIKE` join over `payment` |
| Negative payment | `amount = -45.00` for customer 130 |
| Outlier payment | `amount = 999.99` for customer 459 |
| Impossible rentals | rentals 1001, 2002, 3003 returned three days before they were rented |
| Duplicate customer | a copy of customer 1 (same name, email and address) |

**Growth.** The task role can't read the bucket, so the agent can't compare
against last night's report; it reports activity since the statistics were
last reset instead. For real day-over-day growth, grant `s3:GetObject` on
`reports/*` and `s3:ListBucket` with a `reports/` prefix condition, and
tell the agent to read the previous report first.

## Security notes

- **Least privilege.** The task role allows `rds-db:connect` for
  `dbuser:<resource-id>/agent_ro` and `s3:PutObject` on `reports/*`, and
  nothing else. `agent_ro` has `pg_read_all_data` and `pg_monitor`, and
  defaults to read-only transactions.
- **No API key on the worker.** Only `ANTHROPIC_ENVIRONMENT_ID` and
  `ANTHROPIC_ENVIRONMENT_KEY`, injected by ECS from Secrets Manager.
- **The agent can see its own key.** Its bash commands run in the same
  container as the worker. `worker.py` removes the key from its own
  environment before any tool runs, so child processes don't inherit it,
  but `/proc/1/environ` still holds the value ECS injected, and it is
  readable by the same user. The key only grants this environment's work
  queue, but treat it as exposed to the agent. Running each session in its
  own container (the SDK's poller plus `handle_item()`) removes this.
- **No approvals.** The toolset uses `always_allow`: an unattended run has
  nobody to answer a prompt, and a paused call would wait forever. The
  fences are the IAM role, the database role and the security group.
- **No web.** `web_search` and `web_fetch` run on Anthropic's servers,
  outside your VPC, so they are disabled. The organization's Console web
  settings also apply.
- **Spend cap.** Each scheduled session carries a $5 list-cost budget; at
  the cap it pauses rather than running on.
- **Hardening left out for clarity:** a read-only root filesystem, an
  egress proxy with an allow-list instead of `0.0.0.0/0:443`, and VPC
  interface endpoints to keep AWS API calls off the NAT.

## Costs

Approximate us-east-1 on-demand prices, while the lab is up:

| Item | Rate | Per month |
|---|---|---|
| NAT gateway | $0.045/hour + $0.045/GB | ~$33 + data |
| NAT public IPv4 | $0.005/hour | ~$3.65 |
| RDS `db.t4g.micro` + 20 GB gp3 | $0.016/hour + $0.115/GB-month | ~$14 |
| Fargate worker (0.5 vCPU, 1 GB, always on) | ~$0.025/hour | ~$18 |
| Secrets Manager (2 secrets) | $0.40 each | $0.80 |
| Seed loader (stopped; 8 GB EBS only) | $0.08/GB-month | ~$0.64 |
| ECR, CloudWatch Logs, S3 | storage | under $1 |
| **Infrastructure** | | **~$71** |

On the Anthropic side, each run is billed for **session runtime** ($0.08
per hour while the session is running) plus **tokens** at the model's rates
(`claude-haiku-5-5`: $0.10 per million input tokens and $0.50 per million
output tokens, up to 100K-token prompts). The API is billed through
Console credits, not a Claude Pro or Max subscription. A measured validation run used **TBD**. The NAT gateway is the
largest line: tear the lab down when you're not using it.

## Destroy

```bash
./destroy.sh
```

1. Archives the deployment (stops the schedule), deletes this agent's
   sessions, and archives the agent and the environment.
2. Deletes every object version in the report bucket and every image in
   ECR.
3. `terraform destroy` on `02-worker`, then `01-rds`.

**Left behind at Anthropic:** the archived agent, environment and
deployment (read-only, listed in the Console, no cost) and their deployment
run records. Session history is deleted in step 1. The `claude-lock.json`
and the rendered `agent.md` are removed locally, so the next `apply.sh`
creates fresh resources.

## Files

```
apply.sh / validate.sh / destroy.sh / check_env.sh / run-now.sh / lib.sh
make_diagram.py -> architecture-light.svg, architecture-dark.svg
01-rds/         main, networking, security, postgres, secret, s3, loader, outputs
01-rds/data/    pagila-db.sql, pagila-schema.sql, pagila-data.sql, seed-extras.sql
01-rds/scripts/ load_pagila.sh (loader user_data)
02-worker/      main, ecr, secret, iam, security, ecs, outputs
02-worker/worker/ Dockerfile, worker.py, psql-iam, requirements.txt
03-agent/       environment.yaml, agent.md.tmpl, deployment-nightly.md, run_now.py
```

Pagila is distributed under the license in `01-rds/data/LICENSE.txt`.
