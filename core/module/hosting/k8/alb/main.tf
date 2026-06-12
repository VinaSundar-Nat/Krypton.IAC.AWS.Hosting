# =============================================================================
# main.tf — EKS ALB / Load Balancer Controller Module
#
# Creates:
# 1. Helm release for the AWS Load Balancer Controller.
#
# The LBC is deployed using the official aws/eks-charts Helm repository.
# Service account creation is delegated to the namespace module (Pod Identity);
# the Helm chart is configured with serviceAccount.create = false.
# =============================================================================

locals {
  # Use the first LBC entry when eks_enabled and lbc list is non-empty
  lbc_enabled = var.eks_enabled && length(var.lbc) > 0
  lbc_config  = local.lbc_enabled ? var.lbc[0] : null
}

# ── AWS Load Balancer Controller Helm Release ──────────────────────────────
resource "helm_release" "kr_load_balancer_controller" {
  count = local.lbc_enabled ? 1 : 0

  name       = local.lbc_config.name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = local.lbc_config.namespace

  wait            = true
  wait_for_jobs   = true
  cleanup_on_fail = true

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = tostring(local.lbc_config.service_account.create)
  }

  set {
    name  = "serviceAccount.name"
    value = local.lbc_config.service_account.name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

}
