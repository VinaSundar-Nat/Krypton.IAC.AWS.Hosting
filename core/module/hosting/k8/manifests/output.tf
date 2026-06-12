# =============================================================================
# output.tf — EKS Manifests Module
# =============================================================================

output "gateway_class_name" {
  description = "Name of the created GatewayClass resource."
  value       = length(kubernetes_manifest.kr_alb_gateway_class) > 0 ? var.gateway_manifests.gc_name : ""
}

output "gateway_names" {
  description = "List of created Gateway resource names."
  value       = [for k, gw in kubernetes_manifest.kr_gateway : k]
}
