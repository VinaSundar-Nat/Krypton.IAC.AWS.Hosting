# =============================================================================
# variable.tf — IAM Cluster ALB Module
#
# Inputs for Pod Identity IAM policy creation and EKS Pod Identity association.
# Sourced from pod_identity variable (identity.yml) and cluster_role_arns
# (output of cluster identity module).
# =============================================================================

variable "pod_identity" {
  description = "Pod Identity configuration from identity.yml component.cluster_identity[].pod_identity."
  type = object({
    required     = bool
    cluster_name = string
    roles = list(object({
      role        = string
      role_name   = string
      description = string
      policy = list(object({
        template_location = string
        name              = string
      }))
      service_account = object({
        name      = string
        namespace = string
      })
    }))
  })
  default = {
    required     = false
    cluster_name = ""
    roles        = []
  }
}

variable "cluster_role_arns" {
  description = "Map of IAM role name to ARN from the cluster identity module output."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags applied to IAM resources in this module."
  type        = map(string)
  default     = {}
}
