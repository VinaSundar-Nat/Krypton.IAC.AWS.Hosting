# =============================================================================
# output.tf — Route Table Module
# =============================================================================

output "route_table_ids" {
  description = "Map of route table IDs keyed by route table name (existing or newly created)."
  value       = local.rt_ids
}

output "public_route_table_ids" {
  description = "List of public route table IDs."
  value = [
    for rt in var.route_tables :
    local.rt_ids[rt.name]
    if rt.type == "public"
  ]
}

output "private_route_table_ids" {
  description = "List of private route table IDs."
  value = [
    for rt in var.route_tables :
    local.rt_ids[rt.name]
    if rt.type == "private"
  ]
}

output "route_table_associations" {
  description = "Map of route table associations keyed by unique identifier."
  value = {
    for key, assoc in aws_route_table_association.main : key => {
      subnet_id      = assoc.subnet_id
      route_table_id = assoc.route_table_id
    }
  }
}

output "association_count" {
  description = "Total number of subnet-to-route-table associations created."
  value       = length(aws_route_table_association.main)
}
