# =============================================================================
# output.tf — EKS Launch Template Module
# =============================================================================

output "launch_template_ids" {
  description = "Map of nodegroup identifier to launch template ID"
  value = {
    for key, template in aws_launch_template.kr_nodegroup_launch_template : key => template.id
  }
}

output "launch_template_arns" {
  description = "Map of nodegroup identifier to launch template ARN"
  value = {
    for key, template in aws_launch_template.kr_nodegroup_launch_template : key => template.arn
  }
}

output "launch_template_latest_versions" {
  description = "Map of nodegroup identifier to latest launch template version"
  value = {
    for key, template in aws_launch_template.kr_nodegroup_launch_template : key => template.latest_version
  }
}

output "launch_templates" {
  description = "Complete launch template objects keyed by nodegroup identifier"
  value       = aws_launch_template.kr_nodegroup_launch_template
}
