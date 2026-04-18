# =============================================================================
# main.tf — Internet Gateway Module
#
# Creates or references an existing internet gateway attached to a VPC.
# Validates by Name tag to prevent recreation.
# =============================================================================

locals {
  igw_exists = length(data.aws_internet_gateway.existing.id) > 0
  igw_id     = local.igw_exists ? data.aws_internet_gateway.existing.id : aws_internet_gateway.kr_igw[0].id
}

# ── Check for an existing Internet Gateway by Name tag ──────────────────────────
data "aws_internet_gateway" "existing" {
  filter {
    name   = "tag:Name"
    values = [var.tags["Name"]]
  }

  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# ── Create Internet Gateway only when it doesn't already exist ─────────────────
resource "aws_internet_gateway" "kr_igw" {
  count = !local.igw_exists && var.enabled ? 1 : 0

  vpc_id = var.vpc_id

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}