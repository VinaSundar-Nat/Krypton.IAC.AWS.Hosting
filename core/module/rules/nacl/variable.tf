# =============================================================================
# variable.tf — Network ACL Module
#
# Inputs consumed by the NACL module to create Network ACLs and their
# ingress/egress rules from zone definitions and rule-link declarations.
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where Network ACLs will be created."
  type        = string
}

variable "nacl_zone" {
  description = <<-EOT
    List of NACL zone definitions sourced from rules.yml.
    Each entry carries a logical name, short id, enabled flag, description,
    and a list of subnet names to associate. Only zones with enabled = true
    are created.
  EOT
  type = list(object({
    name        = string
    id          = string
    enabled     = bool
    description = string
    subnets     = list(string)
  }))
  default = []
}

variable "nacl_rule_link" {
  description = <<-EOT
    List of NACL rule link associations sourced from rules.yml.
    nacl references the id field from nacl_zone.
    rules is a list of single-key maps where the key is the rule_id and the
    value carries rule_number, description, cidr_block, subnet name, and action.
    Exactly one of cidr_block or subnet must be non-empty per rule entry.
  EOT
  type = list(object({
    nacl  = string
    rules = list(map(object({
      rule_number = number
      description = string
      cidr_block  = string
      subnet      = string
      action      = string
    })))
  }))
  default = []
}

variable "nacl_rules" {
  description = <<-EOT
    Named NACL rule definitions applied via nacl_rule_link.
    type:     ingress | egress
    protocol: tcp | udp | icmp | -1 (all traffic)
  EOT
  type = list(object({
    id          = string
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    type        = string
  }))
  default = []
}

variable "subnet_static_metadata" {
  description = <<-EOT
    Plan-time deterministic subnet metadata from the subnet module.
    Contains only fields derivable from input variables (no resource IDs).
    Used for for_each key generation in NACL rules to avoid unknown-at-plan-time errors.
  EOT
  type = list(object({
    key        = string
    name       = string
    type       = string
    az         = string
    cidr_block = string
  }))
  default = []
}

variable "subnet_details" {
  description = <<-EOT
    List of subnet detail objects from the subnet module's subnet_details output.
    Used to resolve subnet names to IDs (for nacl_zone.subnets) and
    to CIDR blocks (for rule cidr_block resolution via subnet reference).
  EOT
  type = list(object({
    key        = string
    subnet_id  = string
    name       = string
    cidr_block = string
    type       = string
    az         = string
    vpc_id     = string
  }))
  default = []
}

variable "common_tags" {
  description = "Common tags applied to all NACL resources."
  type        = map(string)
  default     = {}
}
