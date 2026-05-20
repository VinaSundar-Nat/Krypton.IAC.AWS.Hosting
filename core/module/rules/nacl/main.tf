# =============================================================================
# main.tf — Network ACL Module
#
# Step 1 – creates aws_network_acl for every zone where enabled = true.
#          Subnet IDs are resolved by matching nacl_zone.subnets names against
#          subnet_details[*].name (one subnet name maps to N IDs, one per AZ).
#
# Step 2 – creates aws_network_acl_rule for every rule in every nacl_rule_link
#          entry.
#
# Rule resolution:
#   rule_id     → looked up in nacl_rules_by_id for protocol, ports, and type.
#   nacl_id     → matched to aws_network_acl.kr_network_acl key for resource ID.
#   egress      → derived from nacl_rules[*].type ("egress" → true, else false).
#   cidr_block  → rule_cfg.cidr_block when non-empty (direct CIDR).
#                 rule_cfg.subnet when non-empty: one rule per matching subnet
#                 CIDR (expanded across AZs); rule_number offset by AZ index.
# =============================================================================

locals {
  # ── Map of enabled NACLs keyed by logical id ─────────────────────────────
  # e.g. "kr-ect-nacl" => { name, id, enabled, description, subnets }
  enabled_nacls = {
    for nacl in var.nacl_zone : nacl.id => nacl
    if nacl.enabled
  }

  # ── Rule definition lookup map keyed by rule id ───────────────────────────
  nacl_rules_by_id = {
    for r in var.nacl_rules : r.id => r
  }

  # ── Flatten rule links into individual (nacl, rule, cidr) entries ─────────
  # Each entry in nacl_rule_link.rules is a single-key map: { rule_id = cfg }.
  # Rules with a direct cidr_block produce one entry.
  # Rules with a subnet reference expand to one entry per matching subnet CIDR
  # (one per AZ), offsetting rule_number by the subnet index so each NACL rule
  # number remains unique within the NACL.
  nacl_rules_flat = flatten([
    for link_idx, link in var.nacl_rule_link : [
      for rule_map in link.rules : [
        for rule_id, rule_cfg in rule_map :
          rule_cfg.cidr_block != "" ? [
            {
              key         = "${link.nacl}__${rule_id}__${link_idx}__cidr"
              nacl_id     = link.nacl
              rule_id     = rule_id
              rule_number = rule_cfg.rule_number
              description = rule_cfg.description
              cidr_block  = rule_cfg.cidr_block
              action      = rule_cfg.action
            }
          ] : [
            for s_idx, s in [
              for sd in var.subnet_static_metadata : sd
              if sd.name == rule_cfg.subnet
            ] : {
              key         = "${link.nacl}__${rule_id}__${link_idx}__${s_idx}"
              nacl_id     = link.nacl
              rule_id     = rule_id
              rule_number = rule_cfg.rule_number + s_idx
              description = rule_cfg.description
              cidr_block  = s.cidr_block
              action      = rule_cfg.action
            }
          ]
      ]
    ]
  ])

  # ── Keyed map of all flattened rule entries ───────────────────────────────
  nacl_rules_map = {
    for item in local.nacl_rules_flat : item.key => item
  }
}

# =============================================================================
# Step 1: Network ACLs
# One aws_network_acl per enabled zone (enabled = true).
# subnet_ids is resolved by matching each nacl_zone.subnets name against
# subnet_details[*].name — a single name yields one ID per AZ.
# =============================================================================
resource "aws_network_acl" "kr_network_acl" {
  for_each = local.enabled_nacls

  vpc_id = var.vpc_id

  subnet_ids = [
    for s in var.subnet_details : s.subnet_id
    if contains(each.value.subnets, s.name)
  ]

  tags = merge(
    var.common_tags,
    {
      Name = each.value.name
    }
  )

  lifecycle {
    ignore_changes = [tags]
  }
}

# =============================================================================
# Step 2: NACL Rules
# One aws_network_acl_rule per entry in the flattened rule map.
# egress is derived from the nacl_rules type field (egress → true).
# from_port / to_port are set to 0 for protocol = "-1" (all traffic).
# =============================================================================
resource "aws_network_acl_rule" "kr_network_acl_rules" {
  for_each = local.nacl_rules_map

  network_acl_id = aws_network_acl.kr_network_acl[each.value.nacl_id].id

  rule_number = each.value.rule_number
  egress      = local.nacl_rules_by_id[each.value.rule_id].type == "egress"
  protocol    = local.nacl_rules_by_id[each.value.rule_id].protocol
  rule_action = each.value.action
  cidr_block  = each.value.cidr_block

  from_port = local.nacl_rules_by_id[each.value.rule_id].from_port
  to_port   = local.nacl_rules_by_id[each.value.rule_id].to_port

  depends_on = [aws_network_acl.kr_network_acl]
}
