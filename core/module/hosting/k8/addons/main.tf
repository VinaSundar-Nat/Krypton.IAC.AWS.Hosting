# =============================================================================
# main.tf — EKS Addons Module
#
# Creates EKS add-ons driven by configuration flags:
#   - eks-pod-identity-agent: provisioned when pod_identity_required = true
#
# Design is configuration-driven to support future add-on extensions without
# module refactoring.
# =============================================================================

# ── EKS Pod Identity Agent Add-on ────────────────────────────────────────────
# Deploys the eks-pod-identity-agent DaemonSet into the cluster.
# Required for dynamic credential injection into pods via IAM role assumption.
resource "aws_eks_addon" "pod_identity_agent" {
  count = var.eks_enabled && var.pod_identity_required ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}
