# =============================================================================
# variable.tf — EKS Namespace Module
#
# Input variables for Kubernetes namespace provisioning.
# =============================================================================

# ── EKS Enabled Flag ───────────────────────────────────────────────────────────
# Conditional gate for namespace creation. When false, no resources are created.
variable "eks_enabled" {
  description = "Flag to conditionally create Kubernetes namespaces and service accounts. When false, no resources are created."
  type        = bool
  default     = false
}

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

# ── Service Accounts ───────────────────────────────────────────────────────────
# Kubernetes service accounts to provision for workload identity (Pod Identity).
# Sourced from pod_identity.roles[].service_account in identity.yml.
variable "service_accounts" {
  description = <<-EOT
    List of Kubernetes service account definitions to create.
    Used to provision service accounts for Pod Identity workload authentication.
    Each entry includes:
      name      - Kubernetes service account name
      namespace - target namespace (must already exist or be created in this module)
  EOT
  type = list(object({
    name      = string
    namespace = string
  }))
  default = []
}
