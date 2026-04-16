# =============================================================================
# output.tf — NAT Gateway Module
# =============================================================================

output "nat_gateway_ids" {
  description = "Map of AZ -> NAT Gateway ID (existing or newly created)."
  value       = local.nat_gateway_ids
}

output "nat_gateway_id" {
  description = "Single NAT Gateway ID. Useful when single=true; returns the first gateway otherwise."
  value       = values(local.nat_gateway_ids)[0]
}

output "eip_ids" {
  description = "Map of AZ -> Elastic IP allocation ID for newly created NAT gateways."
  value       = { for az, eip in aws_eip.nat : az => eip.id }
}

output "eip_public_ips" {
  description = "Map of AZ -> public IP address allocated for newly created NAT gateways."
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}
