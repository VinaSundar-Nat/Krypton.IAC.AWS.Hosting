# =============================================================================
# variable.tf — IAM Policy Module
#
# Inputs consumed by the policy module to create customer-managed IAM policies
# from statement lists defined in identity.yml component.global.policy[].
# =============================================================================

variable "iam_policies" {
  description = <<-EOT
    List of global IAM policy definitions sourced from identity.yml component.global.policy[].
    template_param holds a JSON-encoded array of IAM policy statement objects used to build
    the policy document. An empty string means no policy document is generated.
  EOT
  type = list(object({
    name           = string
    description    = string
    template_param = string
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all IAM policy resources (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}
