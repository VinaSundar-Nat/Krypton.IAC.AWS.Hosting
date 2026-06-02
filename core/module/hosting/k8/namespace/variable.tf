# =============================================================================
# variable.tf — EKS Namespace Module
#
# Input variables for Kubernetes namespace provisioning.
# =============================================================================

# ── Namespace Map ──────────────────────────────────────────────────────────────
# Flattened namespace definitions with cluster binding information.
# Keyed by cluster_name:namespace_name for deterministic resource naming.
variable "namespace_map" {
  description = <<-EOT
    Map of namespace configurations for Kubernetes namespace provisioning.
    
    Keyed by "cluster_name:namespace_name" for deterministic resource naming.
    Each namespace includes:
      cluster_name - name of the target EKS cluster
      name         - Kubernetes namespace name
      description  - human-readable description
      labels       - map of labels for governance and organization
    
    Sourced from environment/<ENV>/hosting/k8surface.yml component.cluster[].namespace[]
  EOT
  type = map(object({
    cluster_name = string
    name         = string
    description  = string
    labels       = map(string)
  }))
  default = {}
}
