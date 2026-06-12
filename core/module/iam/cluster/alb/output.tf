# =============================================================================
# output.tf — IAM Cluster ALB Module
# =============================================================================

output "lbc_policy_arns" {
  description = "Map of policy key to created LBC IAM policy ARNs."
  value = {
    for k, pol in aws_iam_policy.kr_lbc_policy : k => pol.arn
  }
}

output "pod_identity_association_ids" {
  description = "Map of role name to EKS Pod Identity association IDs."
  value = {
    for k, assoc in aws_eks_pod_identity_association.kr_lbc_auth : k => assoc.association_id
  }
}
