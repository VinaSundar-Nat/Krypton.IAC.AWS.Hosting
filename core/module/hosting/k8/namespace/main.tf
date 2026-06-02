# =============================================================================
# main.tf — EKS Namespace Module
#
# Creates Kubernetes namespaces with governance labels.
# Resources are created only when namespace_map is provided.
# =============================================================================

# ── Create Kubernetes Namespaces ────────────────────────────────────────────────
# For each entry in the namespace_map, create a Kubernetes namespace resource
# with standardized labels for governance, team, and application tracking.
resource "kubernetes_namespace" "kr_cluster_namespace" {
  for_each = var.namespace_map

  metadata {
    name   = each.value.name
    labels = each.value.labels
  }
}
