# =============================================================================
# main.tf — NAT Gateway Module
#
# Creates NAT gateway(s) with EIPs, checking by Name tag before creation.
#
#   single = true  → one NAT gateway placed in the first AZ, shared by all AZs
#   single = false → one NAT gateway per AZ, each with its own EIP
# =============================================================================

locals {
  # When single=true we only care about the first AZ; otherwise all AZs.
  target_azs = var.single ? [var.availability_zones[0]] : var.availability_zones

  # Build the name tag for each target AZ.
  # single mode: just the base name; per-AZ mode: append the AZ suffix.
  nat_names = {
    for az in local.target_azs :
    az => var.single ? var.name : "${var.name}-${az}"
  }
}

# ── Elastic IPs — one per target AZ ───────────────────────────────────────────
resource "aws_eip" "nat" {
  for_each = var.enabled ? local.nat_names : {}

  domain = "vpc"

  tags = merge(
    var.tags,
    { Name = "${each.value}-eip" }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── NAT Gateways ───────────────────────────────────────────────────────────────
resource "aws_nat_gateway" "kr_nat_gateway" {
  for_each = var.enabled ? local.nat_names : {}

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = var.public_subnet_ids[each.key]

  tags = merge(
    var.tags,
    { Name = each.value }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Resolve NAT gateway IDs ────────────────────────────────────────────────────
locals {
  nat_gateway_ids = {
    for az in local.target_azs : az => aws_nat_gateway.kr_nat_gateway[az].id
  }
}
