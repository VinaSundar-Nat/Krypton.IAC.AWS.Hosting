# =============================================================================
# variable.tf — EKS IAM Role Module
#
# Inputs for creating EKS cluster and worker nodegroup IAM roles and their
# managed policy attachments.
#
# Values flow from root module variables populated via identity.auto.tfvars,
# which is generated from environment/<ENV>/platform/identity.yml by
# scripts/replace-vars.sh.
# =============================================================================

# ── Cluster: IAM Roles ────────────────────────────────────────────────────────
# EKS cluster service roles with trust relationships for eks.amazonaws.com.
# Sourced from identity.yml component.cluster[].role[].
variable "cluster_roles" {
  description = "List of EKS cluster IAM role definitions from identity.yml component.cluster[].role[]."
  type = list(object({
    name               = string
    description        = string
    assume_role_policy = string
  }))
  default = []
}

# ── Cluster: Managed Policy Attachments ───────────────────────────────────────
# AWS-managed policies attached to cluster roles (e.g. AmazonEKSClusterPolicy).
# Sourced from identity.yml component.cluster[].policy[].
variable "cluster_policies" {
  description = "List of managed policy attachment definitions for EKS cluster roles from identity.yml component.cluster[].policy[]."
  type = list(object({
    name        = string
    enabled     = bool
    description = string
    arns        = list(string)
    roles       = list(string)
  }))
  default = []
}

# ── Nodegroup: IAM Roles ──────────────────────────────────────────────────────
# EKS worker nodegroup instance roles with trust relationships for ec2.amazonaws.com.
# Sourced from identity.yml component.nodegroup[].role[].
variable "nodegroup_roles" {
  description = "List of EKS worker nodegroup IAM role definitions from identity.yml component.nodegroup[].role[]."
  type = list(object({
    name               = string
    description        = string
    assume_role_policy = string
  }))
  default = []
}

# ── Nodegroup: Managed Policy Attachments ─────────────────────────────────────
# AWS-managed policies attached to nodegroup instance roles (EKS worker node,
# ECR read-only, CNI).
# Sourced from identity.yml component.nodegroup[].policy[].
variable "nodegroup_policies" {
  description = "List of managed policy attachment definitions for EKS worker nodegroup roles from identity.yml component.nodegroup[].policy[]."
  type = list(object({
    name        = string
    enabled     = bool
    description = string
    arns        = list(string)
    roles       = list(string)
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all IAM role resources (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}
