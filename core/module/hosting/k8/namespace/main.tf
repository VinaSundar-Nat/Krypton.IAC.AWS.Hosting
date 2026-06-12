# =============================================================================
# main.tf — EKS Namespace Module
#
# Creates Kubernetes namespaces with governance labels.
# Creates Kubernetes service accounts for Pod Identity workload authentication.
# Resources are created only when namespace_map / service_accounts are provided.
# =============================================================================

# ── Create Kubernetes Namespaces ────────────────────────────────────────────────
# For each entry in the namespace_map, create a Kubernetes namespace resource
# with standardized labels for governance, team, and application tracking.
# Resources are only created when eks_enabled=true.
resource "kubernetes_namespace" "kr_cluster_namespace" {
  for_each = var.eks_enabled ? var.namespace_map : {}

  metadata {
    name   = each.value.name
    labels = each.value.labels
  }
}

# ── Create Kubernetes Service Accounts ─────────────────────────────────────────
# Service accounts used by Pod Identity-enabled workloads (e.g. LBC).
# The service account must exist in the cluster before pod identity associations
# are exercised; the IAM side association is created in the alb IAM module.
resource "kubernetes_service_account" "kr_lbc_sa" {
  for_each = { for sa in var.service_accounts : "${sa.namespace}/${sa.name}" => sa }

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  depends_on = [kubernetes_namespace.kr_cluster_namespace]
}
