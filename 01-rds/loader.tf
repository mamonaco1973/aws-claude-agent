# ===============================================================================
# SEED LOADER HOST
# ===============================================================================
# The database is private, so the sample data has to be loaded from inside
# the VPC. A small Amazon Linux instance in a private subnet does it once
# at first boot and then powers itself off. It has no public IP and no
# ingress rules; an operator can still get a shell through SSM.
# ===============================================================================

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ------------------------------------------------------------------------------
# SEED FILES IN S3
# ------------------------------------------------------------------------------
# The Pagila data file is 3 MB, far over the 16 KB user_data limit, so the
# loader fetches the SQL from the report bucket's seed/ prefix instead.
# ------------------------------------------------------------------------------

resource "aws_s3_object" "seed" {
  for_each = fileset("${path.module}/data", "*.sql")

  bucket = aws_s3_bucket.reports.id
  key    = "seed/${each.value}"
  source = "${path.module}/data/${each.value}"
  etag   = filemd5("${path.module}/data/${each.value}")
}

# ------------------------------------------------------------------------------
# COMPLETION SIGNAL
# ------------------------------------------------------------------------------
# The loader overwrites this with "done" or "failed at line N". Terraform
# owns the parameter so destroy removes it, but ignores the value.
# ------------------------------------------------------------------------------

resource "aws_ssm_parameter" "seed_status" {
  name  = "/claude-agent/seed-status"
  type  = "String"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

# ------------------------------------------------------------------------------
# LOADER IAM
# ------------------------------------------------------------------------------

resource "aws_iam_role" "loader" {
  name = "claude-agent-loader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "loader_ssm" {
  role       = aws_iam_role.loader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "loader" {
  name = "claude-agent-loader"
  role = aws_iam_role.loader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.postgres_credentials.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/seed/*"
      },
      {
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.reports.arn
        Condition = { StringLike = { "s3:prefix" = ["seed/*"] } }
      },
      {
        Effect   = "Allow"
        Action   = "ssm:PutParameter"
        Resource = aws_ssm_parameter.seed_status.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "loader" {
  name = "claude-agent-loader-profile"
  role = aws_iam_role.loader.name
}

# ------------------------------------------------------------------------------
# THE INSTANCE
# ------------------------------------------------------------------------------

resource "aws_instance" "loader" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.loader_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.loader.name
  associate_public_ip_address = false

  # "shutdown -h now" at the end of the script stops, not terminates, so
  # the log stays on disk for inspection.
  instance_initiated_shutdown_behavior = "stop"

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/scripts/load_pagila.sh", {
    region        = var.region
    secret_arn    = aws_secretsmanager_secret.postgres_credentials.arn
    bucket        = aws_s3_bucket.reports.id
    agent_db_user = var.agent_db_user
    status_param  = aws_ssm_parameter.seed_status.name
  })

  # Credentials and seed files must exist before the script runs.
  depends_on = [
    aws_secretsmanager_secret_version.postgres_credentials,
    aws_s3_object.seed,
    aws_iam_role_policy.loader,
    aws_nat_gateway.agent,
    aws_route_table_association.private,
  ]

  tags = {
    Name = "claude-agent-seed-loader"
  }
}
