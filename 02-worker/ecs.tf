# ===============================================================================
# ECS FARGATE: ONE ALWAYS-ON WORKER
# ===============================================================================
# No load balancer, no public IP, no port mappings. The service only keeps
# one copy of the poller alive; Anthropic hands it work by answering its
# long-poll, not by connecting to it.
# ===============================================================================

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/claude-agent-worker"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "agent" {
  name = "claude-agent-cluster"
}

# ------------------------------------------------------------------------------
# TASK DEFINITION
# ------------------------------------------------------------------------------
# The PG* variables are inherited by every bash command the agent runs, so
# "psql-iam -c ..." needs no connection arguments. None of them is secret.
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "worker" {
  family                   = "claude-agent-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.worker.repository_url}:${var.image_tag}"
    essential = true

    # Must cover the SDK's graceful stop (it asks for at least 30 s).
    stopTimeout = 60

    environment = [
      { name = "AWS_REGION", value = local.rds.region },
      { name = "AWS_DEFAULT_REGION", value = local.rds.region },
      { name = "PGHOST", value = local.rds.db_endpoint },
      { name = "PGPORT", value = "5432" },
      { name = "PGDATABASE", value = local.rds.db_name },
      { name = "PGUSER", value = local.rds.agent_db_user },
      { name = "REPORT_BUCKET", value = local.rds.reports_bucket },
    ]

    secrets = [
      {
        name      = "ANTHROPIC_ENVIRONMENT_ID"
        valueFrom = "${aws_secretsmanager_secret.environment.arn}:environment_id::"
      },
      {
        name      = "ANTHROPIC_ENVIRONMENT_KEY"
        valueFrom = "${aws_secretsmanager_secret.environment.arn}:environment_key::"
      },
    ]

    # An init process forwards SIGTERM to the worker; dropping every Linux
    # capability costs nothing for a non-root Python process.
    linuxParameters = {
      initProcessEnabled = true
      capabilities       = { drop = ["ALL"] }
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.worker.name
        awslogs-region        = local.rds.region
        awslogs-stream-prefix = "worker"
      }
    }
  }])
}

# ------------------------------------------------------------------------------
# SERVICE
# ------------------------------------------------------------------------------

resource "aws_ecs_service" "worker" {
  name            = "claude-agent-worker"
  cluster         = aws_ecs_cluster.agent.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.rds.private_subnet_ids
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  # apply.sh forces a new deployment once the image and secret exist, and
  # waits for it there.
  wait_for_steady_state = false
}
