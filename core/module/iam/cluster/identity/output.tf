# =============================================================================
# output.tf — IAM Cluster Identity Module
# =============================================================================

output "cluster_role_arns" {
  description = "Map of cluster identity role name to ARN."
  value = {
    for k, role in aws_iam_role.kr_cluster_role : role.name => role.arn
  }
}

output "group_arns" {
  description = "Map of cluster identity IAM group name to ARN."
  value = {
    for k, group in aws_iam_group.kr_group : group.name => group.arn
  }
}

output "user_arns" {
  description = "Map of cluster identity IAM user name to ARN."
  value = {
    for k, user in aws_iam_user.kr_user : user.name => user.arn
  }
}

output "access_entry_principals" {
  description = "Map of created EKS access entry keys to principal ARNs."
  value = {
    for k, entry in aws_eks_access_entry.kr_cluster_access_entry : k => entry.principal_arn
  }
}
