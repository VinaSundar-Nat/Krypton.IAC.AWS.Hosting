# =============================================================================
# output.tf — EKS Namespace Module
#
# Exports namespace resource information for consumption by root module
# or downstream dependencies.
# =============================================================================

# ── Namespace Resources ─────────────────────────────────────────────────────────
# Complete namespace resource objects indexed by map key (cluster_name:namespace_name).
output "namespaces" {
  description = "Map of created Kubernetes namespace resources keyed by cluster_name:namespace_name"
  value       = kubernetes_namespace.kr_cluster_namespace
}

# ── Namespace Names ──────────────────────────────────────────────────────────────
# List of created Kubernetes namespace names for downstream reference.
output "namespace_names" {
  description = "List of created Kubernetes namespace names"
  value = [
    for ns in kubernetes_namespace.kr_cluster_namespace : ns.metadata[0].name
  ]
}

# ── Namespace IDs ────────────────────────────────────────────────────────────────
# Map of namespace keys to their metadata names for reference in RBAC/quota resources.
output "namespace_ids" {
  description = "Map of namespace keys to their Kubernetes namespace names"
  value = {
    for key, ns in kubernetes_namespace.kr_cluster_namespace :
    key => ns.metadata[0].name
  }
}
