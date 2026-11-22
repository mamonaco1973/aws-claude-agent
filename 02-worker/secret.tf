# ===============================================================================
# ENVIRONMENT CREDENTIALS
# ===============================================================================
# Terraform creates the secret but never its value. apply.sh writes the
# environment ID and the Console-generated environment key straight into
# Secrets Manager, so the key never lands in Terraform state. ECS injects
# both fields into the container as ANTHROPIC_ENVIRONMENT_ID and
# ANTHROPIC_ENVIRONMENT_KEY.
# ===============================================================================

resource "aws_secretsmanager_secret" "environment" {
  name        = "claude-agent-environment"
  description = "Managed Agents self-hosted environment ID and key"

  # Destroy and re-apply must reuse the name, so skip the recovery window.
  recovery_window_in_days = 0
}
