# ===============================================================================
# MASTER CREDENTIALS
# ===============================================================================
# Only the seed loader ever reads this secret. The agent logs in as a
# separate read-only role with a 15-minute IAM token, so no database
# password exists anywhere on the worker.
# ===============================================================================

resource "random_password" "postgres_password" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "postgres_credentials" {
  name        = "claude-agent-postgres-credentials"
  description = "Master credentials for the audit database (loader only)"

  # Destroy and re-apply must reuse the name, so skip the recovery window.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_credentials" {
  secret_id = aws_secretsmanager_secret.postgres_credentials.id
  secret_string = jsonencode({
    user     = "postgres"
    password = random_password.postgres_password.result
    endpoint = aws_db_instance.postgres.address
  })
}
