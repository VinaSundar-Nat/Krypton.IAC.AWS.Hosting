# =============================================================================
# variable.tf — Security Group Module
#
# Inputs consumed by the SG module to create security groups and their
# ingress/egress rules from zone definitions and rule-link declarations.
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where security groups will be created."
  type        = string
}

variable "security_groups_zone" {
  description = <<-EOT
    List of security group zone definitions sourced from rules.yml.
    Each entry carries a logical name, short id, enabled flag, and description.
    Only zones with enabled = true are created.
  EOT
  type = list(object({
    name        = string
    id          = string
    enabled     = bool
    description = string
  }))
  default = []
}

variable "security_group_rule_link" {
  description = <<-EOT
    List of directional rule links between security group zones.
    source / target reference the id field from security_groups_zone.
    rules is a map of rule ID to cidr_blocks override; an empty cidr_blocks
    means the rule uses the SG-to-SG reference (target) instead of a CIDR.
    Exactly one of cidr_blocks or target must be set per rule entry.
  EOT
  type = list(object({
    source      = string
    target      = string
    rules       = map(object({
      cidr_blocks = string
    }))
    description = string
  }))
  default = []
}

variable "security_group_rules" {
  description = <<-EOT
    Named rule definitions applied via security_group_rule_link.
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

variable "common_tags" {
  description = "Common tags applied to all security group resources."
  type        = map(string)
  default     = {}
}
