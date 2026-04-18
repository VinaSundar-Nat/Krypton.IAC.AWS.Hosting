# =============================================================================
# output.tf — Internet Gateway Module
# =============================================================================

output "igw_id" {
  description = "The Internet Gateway ID."
  value       = local.igw_id
}

output "igw_arn" {
  description = "The ARN of the Internet Gateway."
  value       = aws_internet_gateway.kr_igw[0].arn
}

output "igw_owner_id" {
  description = "The ID of the AWS account that owns the internet gateway."
  value       = aws_internet_gateway.kr_igw[0].owner_id
}
