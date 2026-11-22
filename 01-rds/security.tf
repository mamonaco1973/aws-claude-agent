# ===============================================================================
# SECURITY GROUPS
# ===============================================================================
# The database accepts 5432 only from named security groups, never from a
# CIDR. Phase 02 adds the worker's rule to rds_sg; this phase adds only the
# loader's.
# ===============================================================================

resource "aws_security_group" "rds_sg" {
  name        = "claude-agent-rds-sg"
  description = "PostgreSQL, reachable only from named security groups"
  vpc_id      = aws_vpc.agent.id

  tags = {
    Name = "claude-agent-rds-sg"
  }
}

# ------------------------------------------------------------------------------
# LOADER HOST
# ------------------------------------------------------------------------------
# No ingress at all: the loader is reached through SSM Session Manager,
# which is itself an outbound connection from the instance.
# ------------------------------------------------------------------------------

resource "aws_security_group" "loader_sg" {
  name        = "claude-agent-loader-sg"
  description = "Seed loader: no ingress, outbound only"
  vpc_id      = aws_vpc.agent.id

  tags = {
    Name = "claude-agent-loader-sg"
  }
}

# HTTPS out for dnf, S3, Secrets Manager and SSM.
resource "aws_vpc_security_group_egress_rule" "loader_https" {
  security_group_id = aws_security_group.loader_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# HTTP out because the Amazon Linux package mirrors are fetched over 80.
resource "aws_vpc_security_group_egress_rule" "loader_http" {
  security_group_id = aws_security_group.loader_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "loader_pg" {
  security_group_id            = aws_security_group.loader_sg.id
  referenced_security_group_id = aws_security_group.rds_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_loader" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.loader_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Seed loader"
}
