# =============================================================================
# output.tf — EKS NodeGroup Module
# =============================================================================

output "nodegroup_ids" {
  description = "Map of nodegroup identifier to nodegroup ID"
  value = {
    for key, ng in aws_eks_node_group.kr_nodegroup : key => ng.id
  }
}

output "nodegroup_arns" {
  description = "Map of nodegroup identifier to nodegroup ARN"
  value = {
    for key, ng in aws_eks_node_group.kr_nodegroup : key => ng.arn
  }
}

output "nodegroup_names" {
  description = "Map of nodegroup identifier to nodegroup name"
  value = {
    for key, ng in aws_eks_node_group.kr_nodegroup : key => ng.node_group_name
  }
}

output "nodegroup_statuses" {
  description = "Map of nodegroup identifier to nodegroup status"
  value = {
    for key, ng in aws_eks_node_group.kr_nodegroup : key => ng.status
  }
}

output "nodegroup_resources" {
  description = "Map of nodegroup identifier to nodegroup auto scaling group names"
  value = {
    for key, ng in aws_eks_node_group.kr_nodegroup : key => ng.resources
  }
}

output "nodegroups" {
  description = "Complete nodegroup objects keyed by nodegroup identifier"
  value       = aws_eks_node_group.kr_nodegroup
}
