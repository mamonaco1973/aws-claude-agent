# ===============================================================================
# VPC: PUBLIC EDGE, PRIVATE WORKLOADS
# ===============================================================================
# The public subnets exist only to hold the NAT gateway. The database, the
# loader host and the agent worker all sit in the private subnets: they can
# reach out (Anthropic, AWS APIs, package mirrors) but nothing can reach in.
# ===============================================================================

resource "aws_vpc" "agent" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "claude-agent-vpc"
  }
}

resource "aws_internet_gateway" "agent" {
  vpc_id = aws_vpc.agent.id

  tags = {
    Name = "claude-agent-igw"
  }
}

# ------------------------------------------------------------------------------
# PUBLIC SUBNETS (NAT ONLY)
# ------------------------------------------------------------------------------
# No instance, task or database is ever placed here. Public IPs are not
# auto-assigned, so even a mistake would not expose anything by default.
# ------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.agent.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "claude-agent-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.agent.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.agent.id
  }

  tags = {
    Name = "claude-agent-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# NAT GATEWAY
# ------------------------------------------------------------------------------
# One NAT in one AZ keeps the lab cheap. It is the only path to the internet
# for the private subnets, and it only carries connections that start inside.
# ------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "claude-agent-nat-eip"
  }
}

resource "aws_nat_gateway" "agent" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "claude-agent-nat"
  }

  depends_on = [aws_internet_gateway.agent]
}

# ------------------------------------------------------------------------------
# PRIVATE SUBNETS
# ------------------------------------------------------------------------------
# Two AZs because an RDS subnet group requires them, even for a single-AZ
# instance.
# ------------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.agent.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "claude-agent-private-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.agent.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.agent.id
  }

  tags = {
    Name = "claude-agent-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------------------------
# S3 GATEWAY ENDPOINT
# ------------------------------------------------------------------------------
# Free, and it keeps report uploads and the seed download off the NAT
# gateway's per-GB processing charge.
# ------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.agent.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "claude-agent-s3-endpoint"
  }
}
