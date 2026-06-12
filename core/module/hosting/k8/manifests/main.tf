# =============================================================================
# main.tf — EKS Manifests Module
#
# Creates:
# 1. GatewayClass resource — ALB controller integration point.
# 2. Gateway resources — public and private ALB gateway definitions.
#
# Gateway resources depend on the GatewayClass being established first.
# Resources are skipped when eks_enabled = false or gc_name is empty.
# =============================================================================

locals {
  manifests_enabled = var.eks_enabled && var.gateway_manifests.gc_name != ""
}

# ── GatewayClass Resource ────────────────────────────────────────────────────
# Defines the ALB controller as the implementation for all referencing Gateways.
resource "kubernetes_manifest" "kr_alb_gateway_class" {
  count = local.manifests_enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = var.gateway_manifests.gc_name
    }
    spec = {
      controllerName = "gateway.k8s.aws/alb"
    }
  }
}

# ── Gateway Resources ──────────────────────────────────────────────────────────
# Creates one Gateway per entry in the gateway array.
# Each Gateway references the GatewayClass and defines listeners and namespace selectors.
resource "kubernetes_manifest" "kr_gateway" {
  for_each = local.manifests_enabled ? { for gw in var.gateway_manifests.gateway : gw.name => gw } : {}

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name        = each.value.name
      namespace   = each.value.namespace
      annotations = each.value.annotations
    }
    spec = {
      gatewayClassName = each.value.gateway_class
      listeners = [
        for port in each.value.ports : {
          name     = port.name
          port     = port.port
          protocol = port.protocol
          allowedRoutes = {
            namespaces = {
              from = "Selector"
              selector = {
                matchLabels = {
                  for match in each.value.matches : match.name => tostring(match.value)
                }
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.kr_alb_gateway_class]
}
