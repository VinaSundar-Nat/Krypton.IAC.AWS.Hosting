# =============================================================================
# output.tf — Internet Gateway Module
# =============================================================================

output "igw_id" {
  description = "The Internet Gateway ID."
  value       = local.igw_id
}

output "igw_arn" {
  description = "The ARN of the Internet Gateway."
  value       = local.igw_exists ? data.aws_internet_gateways.existing.arns[0] : aws_internet_gateway.main[0].arn
}

output "igw_owner_id" {
  description = "The ID of the AWS account that owns the internet gateway."
  value       = local.igw_exists ? data.aws_internet_gateways.existing.owner_ids[0] : aws_internet_gateway.main[0].owner_id
}
