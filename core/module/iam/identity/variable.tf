# =============================================================================
# variable.tf — IAM Identity Module
#
# Inputs consumed by the identity module to create IAM groups, associate
# policies to groups, create IAM users, and link users to groups.
#
# Values flow from the root module variables populated from identity.yml
# component.global.group[] and component.global.user[].
# =============================================================================

variable "iam_groups" {
  description = <<-EOT
    List of IAM group definitions sourced from identity.yml component.global.group[].
    policies references iam_policies entries by name; ARNs are resolved via policy_arns.
  EOT
  type = list(object({
    name        = string
    description = string
    policies    = list(string)
  }))
  default = []
}

variable "iam_users" {
  description = <<-EOT
    List of IAM user definitions sourced from identity.yml component.global.user[].
    groups references iam_groups entries by name.
    enabled = false excludes the user from creation (disabled without deletion).
  EOT
  type = list(object({
    name        = string
    enabled     = bool
    description = string
    groups      = list(string)
  }))
  default = []
}

variable "policy_arns" {
  description = "Map of policy name to ARN supplied by the policy module output (policy_arns)."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags applied to all IAM user resources (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}
