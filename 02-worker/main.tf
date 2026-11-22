# ===============================================================================
# PHASE 02: THE SELF-HOSTED WORKER
# ===============================================================================
# An always-on Fargate task in the private subnets that long-polls the
# Managed Agents work queue and runs the agent's tools. It reaches out on
# 443 (Anthropic and AWS APIs, through the NAT) and 5432 (the database);
# nothing reaches in. Phase 01's outputs arrive through its state file.
# ===============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

data "terraform_remote_state" "rds" {
  backend = "local"

  config = {
    path = "${path.module}/../01-rds/terraform.tfstate"
  }
}

locals {
  rds = data.terraform_remote_state.rds.outputs
}

provider "aws" {
  region = local.rds.region

  default_tags {
    tags = {
      Project = "aws-claude-agent"
    }
  }
}

# ------------------------------------------------------------------------------
# INPUTS
# ------------------------------------------------------------------------------

variable "image_tag" {
  description = "Worker image tag in ECR (apply.sh pushes latest)"
  type        = string
  default     = "latest"
}

data "aws_caller_identity" "current" {}
