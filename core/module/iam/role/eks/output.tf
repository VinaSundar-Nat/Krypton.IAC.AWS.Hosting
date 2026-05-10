# =============================================================================
# output.tf — EKS IAM Role Module
# =============================================================================

# Map of EKS cluster role name → ARN — consumed by EKS cluster resources.
output "cluster_role_arns" {
  description = "Map of EKS cluster IAM role name to ARN."
  value = {
    for name, role in aws_iam_role.kr_cluster_roles : role.name => role.arn
  }
}

# Map of EKS worker nodegroup role name → ARN — consumed by nodegroup resources.
output "nodegroup_role_arns" {
  description = "Map of EKS worker nodegroup IAM role name to ARN."
  value = {
    for name, role in aws_iam_role.kr_nodegroup_roles : role.name => role.arn
  }
}

# List of created EKS cluster roles with name and arn.
output "cluster_roles" {
  description = "List of created EKS cluster IAM roles with name and arn."
  value = [
    for name, role in aws_iam_role.kr_cluster_roles : {
      name = role.name
      arn  = role.arn
    }
  ]
}

# List of created EKS worker nodegroup roles with name and arn.
output "nodegroup_roles" {
  description = "List of created EKS worker nodegroup IAM roles with name and arn."
  value = [
    for name, role in aws_iam_role.kr_nodegroup_roles : {
      name = role.name
      arn  = role.arn
    }
  ]
}
