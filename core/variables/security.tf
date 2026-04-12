# =============================================================================
# variables/security.tf
#
# Variable declarations for all security resources:
#   Security groups (ingress/egress), NACLs (inbound/outbound).
#
# Values are generated from environment/dev/security/rules.yaml
# by scripts/replace-vars.sh into core/variables/security.auto.tfvars.
#
# Symlinked from core/security.tf so Terraform's root module picks it up.
# =============================================================================

# ── Security Groups ───────────────────────────────────────────────────────────
# One entry per ingress rule. Zone-specific groups are keyed separately in rules.yaml.
variable "sg_ingress_rules" {
  description = <<-EOT
    Ingress rules applied to the application security group.
    protocol: tcp | udp | icmp | -1 (all traffic)
  EOT
  type = list(object({
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_blocks = list(string)
  }))
  default = []
}

variable "sg_egress_rules" {
  description = "Egress rules applied to the application security group."
  type = list(object({
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_blocks = list(string)
  }))
  default = [
    {
      description = "Allow all outbound"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
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
