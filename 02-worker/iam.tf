# ===============================================================================
# IAM: TWO ROLES, TWO AUDIENCES
# ===============================================================================
# The execution role is used by ECS itself, before the container starts,
# to pull the image, read the environment secret and ship logs. The task
# role is what the agent's tool calls run as, so it gets exactly two
# permissions and nothing else.
# ===============================================================================

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------------------------
# EXECUTION ROLE (ECS AGENT)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  name               = "claude-agent-worker-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secret" {
  name = "read-environment-secret"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.environment.arn
    }]
  })
}

# ------------------------------------------------------------------------------
# TASK ROLE (THE AGENT'S TOOLS)
# ------------------------------------------------------------------------------
# rds-db:connect is scoped to one database user on one instance (by its
# resource ID); s3:PutObject to the reports/ prefix. The agent cannot read,
# list or delete reports, and cannot touch the seed/ prefix.
# ------------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  name               = "claude-agent-worker-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "task" {
  name = "audit-db-and-write-reports"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConnectAsReadOnlyUser"
        Effect = "Allow"
        Action = "rds-db:connect"
        Resource = join("", [
          "arn:aws:rds-db:${local.rds.region}:",
          "${data.aws_caller_identity.current.account_id}:dbuser:",
          "${local.rds.db_resource_id}/${local.rds.agent_db_user}",
        ])
      },
      {
        Sid      = "WriteReports"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${local.rds.reports_bucket}/reports/*"
      },
    ]
  })
}
