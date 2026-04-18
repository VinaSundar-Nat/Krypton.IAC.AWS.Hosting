# =============================================================================
# output.tf — Subnet Module
# =============================================================================

output "subnet_ids" {
  description = "Map of created subnet IDs keyed by full identifier (name-az)."
  value = {
    for key, subnet in aws_subnet.kr_subnet : key => subnet.id
  }
}

output "subnets" {
  description = "Map of all created subnet objects keyed by full identifier."
  value = {
    for key, subnet in aws_subnet.kr_subnet : key => subnet
  }
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value = [
    for subnet in aws_subnet.kr_subnet :
    subnet.id
    if lookup(subnet.tags, "Type", "") == "public"
  ]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs."
  value = [
    for subnet in aws_subnet.kr_subnet :
    subnet.id
    if lookup(subnet.tags, "Type", "") == "private"
  ]
}

output "subnet_az_map" {
  description = "Map of subnet names to their availability zones."
  value = {
    for subnet in aws_subnet.kr_subnet :
    lookup(subnet.tags, "Name", "unknown") => subnet.availability_zone...
  }
}

output "created_count" {
  description = "Number of subnets created."
  value       = length(aws_subnet.kr_subnet)
}

output "subnet_details" {
  description = "Detailed information about each created subnet including ID, name, CIDR, and type."
  value = [
    for k, subnet in aws_subnet.kr_subnet : {
      key         = k
      subnet_id   = subnet.id
      name        = lookup(subnet.tags, "Name", "unknown")
      cidr_block  = subnet.cidr_block
      type        = lookup(subnet.tags, "Type", "unknown")
      az          = subnet.availability_zone
      vpc_id      = subnet.vpc_id
    }
  ]
}

