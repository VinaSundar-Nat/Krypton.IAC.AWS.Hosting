# =============================================================================
# main.tf — Subnet Module
#
# Creates subnets with validation and CIDR subnetting based on AZ count.
# Uses forEach to iterate over subnets and validate before creation.
# =============================================================================

locals {
  # Flatten subnet definitions: create one entry per (subnet, az) combination
  subnets_by_az = flatten([
    for subnet in var.subnets : [
      for az_idx, az in subnet.availability_zone : {
        subnet_name    = subnet.name
        subnet_type    = subnet.type
        base_cidr      = subnet.cidr
        az             = az
        az_index       = az_idx
        az_count       = length(subnet.availability_zone)
        full_key       = "${subnet.name}-${az}"
      }
    ]
  ])

  # Build a map for easy lookup
  subnets_map = {
    for item in local.subnets_by_az : item.full_key => item
  }

  # For CIDR calculation reference: calculate how many bits to add based on AZ count
  # e.g., if 2 AZs: add 1 bit (2^1 = 2 subnets), if 4 AZs: add 2 bits (2^2 = 4 subnets)
  # max(..., 1) guards against single-AZ subnets where log(1,2)=0.
  cidr_bits_map = {
    for subnet in var.subnets : subnet.name => max(ceil(log(length(subnet.availability_zone), 2)), 1)
  }
}

# ── Fetch available AZs in the region ──────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── Create subnets with forEach, one per AZ ────────────────────────────────────
resource "aws_subnet" "kr_subnet" {
  for_each = var.enabled && length(var.subnets) > 0 ? local.subnets_map : {}


  vpc_id            = var.vpc_id
  availability_zone = each.value.az

  # Calculate CIDR block by splitting the subnet's own base CIDR across AZs
  # Formula: cidrsubnet(subnet_base_cidr, additional_bits, az_index)
  cidr_block = cidrsubnet(
    each.value.base_cidr,
    local.cidr_bits_map[each.value.subnet_name],
    each.value.az_index
  )

  # Enable DNS hostname assignment for public subnets
  map_public_ip_on_launch = each.value.subnet_type == "public" ? true : false

  tags = merge(
    var.common_tags,
    {
      "Name"   = each.value.subnet_name
      "Type"   = each.value.subnet_type
      "AZ"     = each.value.az
      "Index"  = each.value.az_index
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Data source to fetch created subnets ───────────────────────────────────────
data "aws_subnet" "created" {
  for_each = aws_subnet.kr_subnet

  id = each.value.id

  depends_on = [aws_subnet.kr_subnet]
}