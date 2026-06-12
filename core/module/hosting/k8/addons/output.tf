# =============================================================================
# output.tf — EKS Addons Module
# =============================================================================

output "addon_arns" {
  description = "Map of add-on name to ARN for provisioned EKS add-ons."
  value = merge(
    length(aws_eks_addon.pod_identity_agent) > 0
    ? { "eks-pod-identity-agent" = aws_eks_addon.pod_identity_agent[0].arn }
    : {}
  )
}
