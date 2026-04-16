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

# ── Check for existing NAT Gateways by Name tag (one lookup per target AZ) ────
data "aws_nat_gateways" "existing" {
  for_each = local.nat_names

  filter {
    name   = "tag:Name"
    values = [each.value]
  }

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  # Only consider active gateways.
  filter {
    name   = "state"
    values = ["available", "pending"]
  }
}

# ── Elastic IPs — one per target AZ, created only when the NAT GW is new ──────
resource "aws_eip" "nat" {
  for_each = {
    for az, name in local.nat_names :
    az => name
    if var.enabled && length(data.aws_nat_gateways.existing[az].ids) == 0
  }

  domain = "vpc"

  tags = merge(
    var.tags,
    { Name = "${each.value}-eip" }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── NAT Gateways — skipped when an existing gateway with the same name exists ──
resource "aws_nat_gateway" "kr_nat_gateway" {
  for_each = {
    for az, name in local.nat_names :
    az => name
    if var.enabled && length(data.aws_nat_gateways.existing[az].ids) == 0
  }

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

# ── Resolve final NAT gateway IDs (existing or newly created) ──────────────────
locals {
  nat_gateway_ids = {
    for az, name in local.nat_names :
    az => (
      length(data.aws_nat_gateways.existing[az].ids) > 0
        ? data.aws_nat_gateways.existing[az].ids[0]
        : aws_nat_gateway.kr_nat_gateway[az].id
    )
  }
}
