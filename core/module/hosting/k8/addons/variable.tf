# =============================================================================
# variable.tf — EKS Addons Module
#
# Input variables for EKS add-on provisioning.
# Add-ons are created conditionally based on cluster opt-in and component flags.
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name to install add-ons into."
  type        = string
  default     = ""
}

variable "eks_enabled" {
  description = "Feature flag — skip add-on provisioning when EKS is not opted in."
  type        = bool
  default     = false
}

variable "pod_identity_required" {
  description = "When true, provisions the eks-pod-identity-agent add-on."
  type        = bool
  default     = false
}
