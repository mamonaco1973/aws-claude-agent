# ===============================================================================
# OUTPUTS (consumed by phase 02 and the shell scripts)
# ===============================================================================

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.agent.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "rds_sg_id" {
  value = aws_security_group.rds_sg.id
}

output "db_endpoint" {
  value = aws_db_instance.postgres.address
}

output "db_name" {
  value = "pagila"
}

# The rds-db:connect ARN is built from the resource ID, not the identifier.
output "db_resource_id" {
  value = aws_db_instance.postgres.resource_id
}

output "agent_db_user" {
  value = var.agent_db_user
}

output "reports_bucket" {
  value = aws_s3_bucket.reports.id
}

output "seed_status_param" {
  value = aws_ssm_parameter.seed_status.name
}
