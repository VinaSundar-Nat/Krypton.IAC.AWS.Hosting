# =============================================================================
# variable.tf — IAM Cluster Identity Module
#
# Inputs for IAM roles, groups, users, and EKS access entries sourced from
# identity.yml component.cluster_identity[].
# =============================================================================

variable "cluster_identity_roles" {
  description = "Cluster identity IAM role definitions from identity.yml component.cluster_identity[].roles[]."
  type = list(object({
    cluster_name = string
    name         = string
    sid          = string
    description  = string
    version      = string
    effect       = string
    actions      = list(string)
    principals = list(object({
      type  = string
      value = string
    }))
  }))
  default = []
}

variable "cluster_identity_groups" {
  description = "Cluster identity IAM groups from identity.yml component.cluster_identity[].groups[]."
  type = list(object({
    cluster_name = string
    name         = string
    assume_role  = string
  }))
  default = []
}

variable "cluster_identity_users" {
  description = "Cluster identity IAM users from identity.yml component.cluster_identity[].groups[].users[]."
  type = list(object({
    cluster_name  = string
    group_name    = string
    name          = string
    enabled       = bool
    force_destroy = bool
    namespace     = string
    policy_arn    = string
    k8group       = list(string)
    description   = string
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to IAM and EKS access resources in this module."
  type        = map(string)
  default     = {}
}
