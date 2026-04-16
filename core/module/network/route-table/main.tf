
# =============================================================================
# main.tf — Route Table Module
#
# Creates route tables (public/private), adds dynamic routes, and associates
# subnets. Mirrors the VPC module pattern: checks for existing route tables
# by Name tag before creating — never recreates if one already exists.
# =============================================================================

locals {
  # Build route table map keyed by name
  route_tables_map = {
    for rt in var.route_tables : rt.name => rt
  }

  # Per-table: whether an existing route table was found by Name tag
  rt_exists = {
    for rt_name, rt in local.route_tables_map :
    rt_name => length(data.aws_route_tables.existing[rt_name].ids) > 0
  }

  # Resolve the ID — use the existing one if found, otherwise the newly created one
  rt_ids = {
    for rt_name, rt in local.route_tables_map :
    rt_name => (
      local.rt_exists[rt_name]
      ? data.aws_route_tables.existing[rt_name].ids[0]
      : aws_route_table.kr_route_table[rt_name].id
    )
  }

  # Flatten subnets for association by type
  subnet_associations = flatten([
    for rt_name, rt in local.route_tables_map : [
      for subnet in var.subnet_details :
      {
        route_table_name = rt_name
        route_table_type = rt.type
        subnet_id        = subnet.subnet_id
        subnet_type      = subnet.type
        subnet_name      = subnet.name
        az_key           = "${rt_name}-${subnet.subnet_id}"
      }
      if subnet.type == rt.type
    ]
  ])

  # Flatten routes for dynamic creation
  # Format: "rt_name-route_index" => { route_table_name, destination, target, ... }
  flattened_routes = flatten([
    for rt_name, rt in local.route_tables_map : [
      for route_idx, route in rt.routes : {
        key              = "${rt_name}-${route_idx}"
        route_table_name = rt_name
        destination      = route.destination
        target           = route.target
        type             = rt.type
      }
    ]
  ])

  routes_map = {
    for route in local.flattened_routes : route.key => route
  }
}

# ── Check for existing Route Tables by Name tag (returns empty list — never errors) ──
data "aws_route_tables" "existing" {
  for_each = var.enabled ? local.route_tables_map : {}

  vpc_id = var.vpc_id

  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

# ── Create only when no matching Route Table exists ───────────────────────────
resource "aws_route_table" "kr_route_table" {
  for_each = {
    for rt_name, rt in local.route_tables_map :
    rt_name => rt
    if var.enabled && !local.rt_exists[rt_name]
  }

  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      "Name" = each.key
      "Type" = each.value.type
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# ── Add routes dynamically based on route definitions ────────────────────────────
# Routes are only added to newly created tables; existing tables retain their routes.
resource "aws_route" "kr_rt_routes" {
  for_each = {
    for key, route in local.routes_map :
    key => route
    if var.enabled && !local.rt_exists[route.route_table_name]
  }

  route_table_id         = local.rt_ids[each.value.route_table_name]
  destination_cidr_block = each.value.destination

  # Route to Internet Gateway - check if target contains internet gateway identifier
  gateway_id = (
    each.value.type == "public" && can(regex("internet", lower(each.value.target)))
    ? var.internet_gateway_id
    : null
  )

  # Route to NAT Gateway - check if target contains nat gateway identifier
  nat_gateway_id = (
    each.value.type == "private" && can(regex("nat", lower(each.value.target)))
    ? var.nat_gateway_id
    : null
  )

  depends_on = [aws_route_table.kr_route_table]
}

# ── Associate subnets with route tables by type ────────────────────────────────
resource "aws_route_table_association" "main" {
  for_each = {
    for assoc in local.subnet_associations : assoc.az_key => assoc
    if var.enabled
  }

  subnet_id      = each.value.subnet_id
  route_table_id = local.rt_ids[each.value.route_table_name]

  depends_on = [aws_route_table.kr_route_table]
}