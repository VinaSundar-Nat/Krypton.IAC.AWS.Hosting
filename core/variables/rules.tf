# =============================================================================
# variables/rules.tf
#
# Variable declarations for all security resources:
#   Security group zones, links, rules, and NACLs (inbound/outbound).
#
# Values are generated from environment/<ENV>/platform/rules.yml
# by scripts/replace-vars.sh into core/variables/rules.auto.tfvars.
#
# Symlinked from core/rules.tf so Terraform's root module picks it up.
# =============================================================================

# ── Security Group Zones ──────────────────────────────────────────────────────
# Named security groups per zone (e.g. app-rst, web-ect, app-ict).
# Sourced from rules.yml component.security_group.security_groups_zone[].
variable "security_groups_zone" {
  description = <<-EOT
    List of security group zone definitions sourced from rules.yml.
    Each entry carries a logical name, short id, enabled flag, and description.
  EOT
  type = list(object({
    name        = string
    id          = string
    enabled     = bool
    description = string
  }))
  default = []
}

# ── Security Group Rule Links ─────────────────────────────────────────────────
# Directed associations between security groups with per-rule cidr_blocks overrides.
# Sourced from rules.yml component.security_group.security_group_rule_link[].
variable "security_group_rule_link" {
  description = <<-EOT
    List of directional links between security group zones.
    source / target reference the id field from security_groups_zone.
    rules is a map of rule ID to cidr_blocks override; an empty cidr_blocks
    means the rule uses the SG-to-SG reference instead of a CIDR.
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

# ── Security Group Rules ──────────────────────────────────────────────────────
# Reusable rule definitions referenced by id in security_group_links.
# Sourced from rules.yml component.security_group.rules[].
variable "security_group_rules" {
  description = <<-EOT
    Named rule definitions applied via security_group_links.
    type: ingress | egress
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

# ── NACLs – private subnets ───────────────────────────────────────────────────
variable "nacl_inbound_rules" {
  description = <<-EOT
    Inbound NACL rules for private subnets (app, data, cache zones).
    rule_number: evaluated lowest-first, must be unique.
    action: allow | deny
    protocol: tcp | udp | icmp | -1
  EOT
  type = list(object({
    rule_number = number
    protocol    = string
    action      = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

variable "nacl_outbound_rules" {
  description = "Outbound NACL rules for private subnets."
  type = list(object({
    rule_number = number
    protocol    = string
    action      = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

# ── NACLs – public subnets ────────────────────────────────────────────────────
variable "nacl_public_inbound_rules" {
  description = "Inbound NACL rules for public subnets (web zone)."
  type = list(object({
    rule_number = number
    protocol    = string
    action      = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}

variable "nacl_public_outbound_rules" {
  description = "Outbound NACL rules for public subnets (web zone)."
  type = list(object({
    rule_number = number
    protocol    = string
    action      = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = []
}
