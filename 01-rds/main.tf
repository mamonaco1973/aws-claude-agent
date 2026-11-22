# ===============================================================================
# PHASE 01: PRIVATE DATABASE, NETWORK AND REPORT BUCKET
# ===============================================================================
# Everything the agent will look at or write to, and nothing it runs on:
# a VPC whose database and workloads live in private subnets behind a NAT
# gateway, an RDS PostgreSQL instance loaded with Pagila, and the S3 bucket
# that receives the nightly reports. Phase 02 reads these outputs through
# terraform_remote_state.
# ===============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource carries the project tag, so the lab is easy to find in
  # the console and in Cost Explorer.
  default_tags {
    tags = {
      Project = "aws-claude-agent"
    }
  }
}

# ------------------------------------------------------------------------------
# INPUTS
# ------------------------------------------------------------------------------

variable "region" {
  description = "AWS region for the whole lab"
  type        = string
  default     = "us-east-1"
}

variable "agent_db_user" {
  description = "Read-only PostgreSQL role the agent logs in as (IAM auth)"
  type        = string
  default     = "agent_ro"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
