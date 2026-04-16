# =============================================================================
# output.tf — Subnet Module
# =============================================================================

output "subnet_ids" {
  description = "Map of created subnet IDs keyed by full identifier (name-az)."
  value = {
    for key, subnet in aws_subnet.kr_subnet : key => subnet[0].id
  }
}

output "subnets" {
  description = "Map of all created subnet objects keyed by full identifier."
  value = {
    for key, subnet in aws_subnet.kr_subnet : key => subnet[0]
  }
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value = [
    for subnet in aws_subnet.kr_subnet :
    subnet[0].id
    if lookup(subnet[0].tags, "Type", "") == "public"
  ]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs."
  value = [
    for subnet in aws_subnet.kr_subnet :
    subnet[0].id
    if lookup(subnet[0].tags, "Type", "") == "private"
  ]
}

output "subnet_az_map" {
  description = "Map of subnet names to their availability zones."
  value = {
    for subnet in aws_subnet.kr_subnet :
    lookup(subnet[0].tags, "Name", "unknown") => subnet[0].availability_zone
  }
}

output "created_count" {
  description = "Number of subnets created."
  value       = length(aws_subnet.kr_subnet)
}

output "subnet_details" {
  description = "Detailed information about each created subnet including ID, name, CIDR, and type."
  value = [
    for subnet in aws_subnet.kr_subnet : {
      subnet_id   = subnet[0].id
      name        = lookup(subnet[0].tags, "Name", "unknown")
      cidr_block  = subnet[0].cidr_block
      type        = lookup(subnet[0].tags, "Type", "unknown")
      az          = subnet[0].availability_zone
      vpc_id      = subnet[0].vpc_id
    }
  ]
}

