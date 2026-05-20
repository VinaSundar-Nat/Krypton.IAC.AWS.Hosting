# =============================================================================
# variables/k8hosting.tf
#
# Variable declarations for EKS cluster and nodegroup resources:
#   Clusters, nodegroups, launch templates, scaling configurations.
#
# Values are generated from environment/<ENV>/hosting/k8surface.yml
# by scripts/replace-vars.sh into core/variables/k8hosting.auto.tfvars.
#
# Symlinked from core/k8hosting.tf so Terraform's root module picks it up.
# =============================================================================

# ── EKS Clusters ──────────────────────────────────────────────────────────────
# EKS cluster control plane definitions with nodegroup configurations.
# Sourced from k8surface.yml component.cluster[].
# ── EKS Enabled Flag ──────────────────────────────────────────────────────────
# Feature flag to determine if EKS is required for this component.
# Sourced from k8surface.yml component.opt-in.
variable "eks_enabled" {
  description = "Feature flag indicating whether EKS is required for this component (opt-in from k8surface.yml)."
  type        = bool
  default     = false
}

# ── EKS Clusters ──────────────────────────────────────────────────────────────
# EKS cluster control plane definitions with nodegroup configurations.
# Sourced from k8surface.yml component.cluster[].
variable "eks_clusters" {
  description = <<-EOT
    List of EKS cluster definitions sourced from k8surface.yml component.cluster[].
    Each cluster includes nodegroup definitions nested within the cluster object.
    subnets: list of subnet names/IDs for the cluster.
    security_groups: list of security group names/IDs.
    endpoint_public_access, endpoint_private_access: boolean flags for API endpoint access.
    nodegroups: nested list of nodegroup definitions for this cluster.
  EOT
  type = list(object({
    name                    = string
    mode                    = string
    role                    = string
    version                 = string
    subnets                 = list(string)
    security_groups         = list(string)
    endpoint_public_access  = bool
    endpoint_private_access = bool
    nodegroups              = list(object({
      name        = string
      description = string
      role        = string
      template    = string
      subnets     = list(string)
      template_parameters = object({
        name                  = string
        name_prefix           = string
        description           = string
        security_groups       = list(string)
        block_device_mappings = object({
          device_name           = string
          type                  = string
          volume_size           = number
          volume_type           = string
          delete_on_termination = bool
          encrypted             = bool
        })
        monitoring = object({
          enabled = bool
        })
        lifecycle = object({
          create_before_destroy = bool
        })
        tags = map(string)
      })
      machine = object({
        instance_types = list(string)
        ami_type       = string
        capacity_type  = string
      })
      scaling_config = object({
        desired_size = number
        max_size     = number
        min_size     = number
      })
    }))
  }))
  default = []
}
