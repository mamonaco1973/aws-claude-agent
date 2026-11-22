# ===============================================================================
# RDS FOR POSTGRESQL: THE DATABASE THE AGENT AUDITS
# ===============================================================================
# Private, single-AZ and small: the point is the network position, not
# availability. IAM database authentication is on so the agent can log in
# with a short-lived token signed by its ECS task role.
# ===============================================================================

# ------------------------------------------------------------------------------
# PARAMETER GROUP
# ------------------------------------------------------------------------------
# pg_stat_statements has to be preloaded before the agent can find slow
# queries; setting it explicitly avoids depending on the engine default.
# ------------------------------------------------------------------------------

resource "aws_db_parameter_group" "postgres" {
  name   = "claude-agent-postgres17"
  family = "postgres17"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  # Gives the audit real I/O timings in pg_stat_statements.
  parameter {
    name  = "track_io_timing"
    value = "1"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "claude-agent-postgres-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "claude-agent-postgres-subnets"
  }
}

resource "aws_db_instance" "postgres" {
  identifier        = "claude-agent-postgres"
  engine            = "postgres"
  engine_version    = "17"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "postgres"
  username = "postgres"
  password = random_password.postgres_password.result

  parameter_group_name   = aws_db_parameter_group.postgres.name
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # The whole lab hinges on these two lines.
  publicly_accessible                 = false
  iam_database_authentication_enabled = true

  multi_az                = false
  backup_retention_period = 1
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = {
    Name = "claude-agent-postgres"
  }
}
