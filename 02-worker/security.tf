# ===============================================================================
# WORKER SECURITY GROUP: OUTBOUND ONLY
# ===============================================================================
# Zero ingress rules, on purpose: the worker dials out to Anthropic's work
# queue and is never dialled. Terraform also removes the default allow-all
# egress rule, so the two egress rules below are the complete list.
# validate.sh prints the rule count to prove it.
# ===============================================================================

resource "aws_security_group" "worker" {
  name        = "claude-agent-worker-sg"
  description = "Agent worker: no ingress; egress 443 and 5432 to RDS only"
  vpc_id      = local.rds.vpc_id

  tags = {
    Name = "claude-agent-worker-sg"
  }
}

# Anthropic's work queue and the AWS APIs (S3 rides the gateway endpoint
# but still needs this rule). RDS auth tokens are signed locally: no call.
resource "aws_vpc_security_group_egress_rule" "worker_https" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS: Anthropic work queue and AWS APIs"
}

resource "aws_vpc_security_group_egress_rule" "worker_pg" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = local.rds.rds_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL to the audit database"
}

# The matching rule on the database side.
resource "aws_vpc_security_group_ingress_rule" "rds_from_worker" {
  security_group_id            = local.rds.rds_sg_id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Claude agent worker"
}
