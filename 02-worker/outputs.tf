# ===============================================================================
# OUTPUTS (consumed by apply.sh, validate.sh and destroy.sh)
# ===============================================================================

output "ecr_repository_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.worker.name
}

output "environment_secret_arn" {
  value = aws_secretsmanager_secret.environment.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.agent.name
}

output "service_name" {
  value = aws_ecs_service.worker.name
}

output "worker_sg_id" {
  value = aws_security_group.worker.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.worker.name
}
