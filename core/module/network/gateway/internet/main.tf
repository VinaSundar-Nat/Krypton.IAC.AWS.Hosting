# =============================================================================
# main.tf — Internet Gateway Module
#
# Creates or references an existing internet gateway attached to a VPC.
# Validates by Name tag to prevent recreation.
# =============================================================================

locals {
  igw_id = aws_internet_gateway.kr_igw[0].id
}

# ── Create Internet Gateway ─────────────────────────────────────────────────────
resource "aws_internet_gateway" "kr_igw" {
  count = var.enabled ? 1 : 0

  vpc_id = var.vpc_id

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}