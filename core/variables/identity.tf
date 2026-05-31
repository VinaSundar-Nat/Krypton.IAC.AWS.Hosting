# =============================================================================
# variables/identity.tf
#
# Variable declarations for all IAM identity resources:
#   Global policies, groups, users; EKS cluster and nodegroup roles and policies.
#
# Values are generated from environment/<ENV>/platform/identity.yml
# by scripts/replace-vars.sh into core/variables/identity.auto.tfvars.
#
# Symlinked from core/identity.tf so Terraform's root module picks it up.
# =============================================================================

# ── Global: IAM Policies ──────────────────────────────────────────────────────
# Custom IAM policies shared across groups/roles.
# Sourced from identity.yml component.global.policy[].
variable "iam_policies" {
  description = <<-EOT
    List of global IAM policy definitions sourced from identity.yml component.global.policy[].
    template_param holds a JSON-encoded array of IAM policy statement objects used to build
    the policy document.
  EOT
  type = list(object({
    name           = string
    description    = string
    template_param = string
  }))
  default = []
}

# ── Global: IAM Groups ────────────────────────────────────────────────────────
# IAM groups bundling one or more policies for assignment to users.
# Sourced from identity.yml component.global.group[].
variable "iam_groups" {
  description = <<-EOT
    List of IAM group definitions sourced from identity.yml component.global.group[].
    policies references iam_policies entries by name.
  EOT
  type = list(object({
    name        = string
    description = string
    policies    = list(string)
  }))
  default = []
}

# ── Global: IAM Users ─────────────────────────────────────────────────────────
# IAM users and their group memberships.
# Sourced from identity.yml component.global.user[].
variable "iam_users" {
  description = <<-EOT
    List of IAM user definitions sourced from identity.yml component.global.user[].
    groups references iam_groups entries by name.
    enabled = false disables console access without deleting the user.
  EOT
  type = list(object({
    name        = string
    enabled     = bool
    description = string
    groups      = list(string)
  }))
  default = []
}

# ── Cluster: IAM Roles ────────────────────────────────────────────────────────
# EKS cluster service roles with trust relationships for eks.amazonaws.com.
# Sourced from identity.yml component.cluster[].role[].
variable "cluster_roles" {
  description = <<-EOT
    List of EKS cluster IAM role definitions sourced from identity.yml component.cluster[].role[].
    assume_role_policy is the JSON-encoded trust relationship policy document.
  EOT
  type = list(object({
    name               = string
    description        = string
    assume_role_policy = string
  }))
  default = []
}

# ── Cluster: Managed Policy Attachments ───────────────────────────────────────
# AWS-managed and customer-managed policies attached to cluster roles.
# Sourced from identity.yml component.cluster[].policy[].
variable "cluster_policies" {
  description = <<-EOT
    List of managed policy attachment definitions for EKS cluster roles sourced from
    identity.yml component.cluster[].policy[].
    arns holds the ARNs of the managed policies to attach.
    roles references cluster_roles entries by name to attach this policy.
  EOT
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
  description = <<-EOT
    List of EKS worker nodegroup IAM role definitions sourced from
    identity.yml component.nodegroup[].role[].
    assume_role_policy is the JSON-encoded trust relationship policy document.
  EOT
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
  description = <<-EOT
    List of managed policy attachment definitions for EKS worker nodegroup roles
    sourced from identity.yml component.nodegroup[].policy[].
    arns holds the ARNs of the managed policies to attach.
    roles references nodegroup_roles entries by name to attach this policy.
  EOT
  type = list(object({
    name        = string
    enabled     = bool
    description = string
    arns        = list(string)
    roles       = list(string)
  }))
  default = []
}

# ── Cluster: Access Entries ───────────────────────────────────────────────────
# IAM principals (roles/users) granted Kubernetes API access via EKS access entries.
# Sourced from identity.yml component.cluster[].access[].
variable "cluster_access" {
  description = <<-EOT
    List of EKS access entry definitions sourced from identity.yml component.cluster[].access[].
    Each entry grants an IAM role access to the Kubernetes API with the given EKS access policy.
    role_name is the IAM role name (without account ID prefix).
    principal_arn is constructed in the module as: arn:aws:iam::<account>:role/<role_name>
    access_scope: "cluster" for full cluster scope, "namespace" for namespace scope.
  EOT
  type = list(object({
    cluster_name = string
    role_name    = string
    description  = string
    policy_arn   = string
    access_scope = string
  }))
  default = []
}

# ── Cluster Identity: Roles ──────────────────────────────────────────────────
# IAM roles used by human/admin identities to access EKS clusters.
# Sourced from identity.yml component.cluster_identity[].roles[].
variable "cluster_identity_roles" {
  description = <<-EOT
    List of cluster identity IAM role definitions from identity.yml component.cluster_identity[].roles[].
    principal may include the literal "$${account_id}" placeholder, replaced at apply time.
    sid is used by groups (assume_role) to map to the target role.
  EOT
  type = list(object({
    cluster_name = string
    name         = string
    sid          = string
    description  = string
    version      = string
    effect       = string
    actions      = list(string)
    principal    = string
  }))
  default = []
}

# ── Cluster Identity: Groups ─────────────────────────────────────────────────
# IAM groups for cluster access; each points to a role SID via assume_role.
# Sourced from identity.yml component.cluster_identity[].groups[].
variable "cluster_identity_groups" {
  description = <<-EOT
    List of cluster identity IAM groups from identity.yml component.cluster_identity[].groups[].
    assume_role references cluster_identity_roles.sid within the same cluster_name.
  EOT
  type = list(object({
    cluster_name = string
    name         = string
    assume_role  = string
  }))
  default = []
}

# ── Cluster Identity: Users ──────────────────────────────────────────────────
# IAM users assigned to cluster identity groups.
# Sourced from identity.yml component.cluster_identity[].groups[].users[].
variable "cluster_identity_users" {
  description = <<-EOT
    List of cluster identity IAM users from identity.yml component.cluster_identity[].groups[].users[].
    group_name references cluster_identity_groups.name in the same cluster_name.
    namespace is mapped to IAM user path when provided.
    k8group is mapped to EKS access entry kubernetes_groups for the linked cluster identity role.
  EOT
  type = list(object({
    cluster_name  = string
    group_name    = string
    name          = string
    enabled       = bool
    force_destroy = bool
    namespace     = string
    k8group       = list(string)
    description   = string
  }))
  default = []
}
