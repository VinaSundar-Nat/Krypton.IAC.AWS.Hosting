# =============================================================================
# main.tf — Security Group Module
#
# Step 1 – creates aws_security_group for every zone where enabled = true.
#
# Step 2 – creates aws_vpc_security_group_ingress_rule or
#           aws_vpc_security_group_egress_rule for every rule in every
#           security_group_rule_link entry.
#
# Rule resolution:
#   source  → security_group_id (the "from" group).
#   target  → referenced_security_group_id when non-empty (SG-to-SG).
#   rules[*].cidr_blocks → cidr_ipv4 when non-empty (CIDR-based).
#   Exactly one of cidr_ipv4 or referenced_security_group_id must be set;
#   if both are empty AWS will reject the resource.
#   from_port / to_port are omitted when ip_protocol = "-1" (all traffic).
# =============================================================================

locals {
  # ── Map of enabled security groups keyed by logical id ───────────────────
  # e.g. "kr-app-rst" => { name, id, enabled, description }
  enabled_sgs = {
    for sg in var.security_groups_zone : sg.id => sg
    if sg.enabled
  }

  # ── Rule definition lookup map keyed by rule id ───────────────────────────
  rules_by_id = {
    for r in var.security_group_rules : r.id => r
  }

  # ── Flatten rule links into individual (link, rule) entries ───────────────
  # link_idx is embedded in the key so that the same rule_id can legitimately
  # appear in multiple links (e.g. eg003 is used in both link 2 and link 4).
  sg_rules_flat = flatten([
    for link_idx, link in var.security_group_rule_link : [
      for rule_id, rule_cfg in link.rules : {
        key         = "${link.source}__${rule_id}__${link_idx}"
        source      = link.source
        target      = link.target
        rule_id     = rule_id
        cidr_ipv4   = rule_cfg.cidr_blocks
        description = link.description
      }
    ]
  ])

  # ── Keyed map of all flattened rule entries ───────────────────────────────
  sg_rules_map = {
    for item in local.sg_rules_flat : item.key => item
  }

  # ── Ingress-only subset ───────────────────────────────────────────────────
  sg_ingress_rules = {
    for k, v in local.sg_rules_map : k => v
    if local.rules_by_id[v.rule_id].type == "ingress"
  }

  # ── Egress-only subset ────────────────────────────────────────────────────
  sg_egress_rules = {
    for k, v in local.sg_rules_map : k => v
    if local.rules_by_id[v.rule_id].type == "egress"
  }
}

# =============================================================================
# Step 1: Security Groups
# One aws_security_group per enabled zone (enabled = true).
# =============================================================================
resource "aws_security_group" "kr_security_group" {
  for_each = local.enabled_sgs

  name        = each.value.name
  description = each.value.description
  vpc_id      = var.vpc_id

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
# Step 2a: Ingress Rules
# aws_vpc_security_group_ingress_rule for every ingress link entry.
# =============================================================================
resource "aws_vpc_security_group_ingress_rule" "kr_sg_ingress" {
  for_each = local.sg_ingress_rules

  security_group_id = aws_security_group.kr_security_group[each.value.source].id

  # Populated when the link rule carries a non-empty cidr_blocks value.
  cidr_ipv4 = each.value.cidr_ipv4 != "" ? each.value.cidr_ipv4 : null

  # Populated when the link has a non-empty target (SG-to-SG reference).
  referenced_security_group_id = (
    each.value.target != ""
    ? aws_security_group.kr_security_group[each.value.target].id
    : null
  )

  # Port range is irrelevant for ip_protocol = "-1" (all traffic).
  from_port   = local.rules_by_id[each.value.rule_id].protocol != "-1" ? local.rules_by_id[each.value.rule_id].from_port : null
  to_port     = local.rules_by_id[each.value.rule_id].protocol != "-1" ? local.rules_by_id[each.value.rule_id].to_port : null
  ip_protocol = local.rules_by_id[each.value.rule_id].protocol

  description = each.value.description

  tags = merge(
    var.common_tags,
    {
      Name = "${each.value.source}-${each.value.rule_id}"
    }
  )

  depends_on = [aws_security_group.kr_security_group]
}

# =============================================================================
# Step 2b: Egress Rules
# aws_vpc_security_group_egress_rule for every egress link entry.
# =============================================================================
resource "aws_vpc_security_group_egress_rule" "kr_sg_egress" {
  for_each = local.sg_egress_rules

  security_group_id = aws_security_group.kr_security_group[each.value.source].id

  # Populated when the link rule carries a non-empty cidr_blocks value.
  cidr_ipv4 = each.value.cidr_ipv4 != "" ? each.value.cidr_ipv4 : null

  # Populated when the link has a non-empty target (SG-to-SG reference).
  referenced_security_group_id = (
    each.value.target != ""
    ? aws_security_group.kr_security_group[each.value.target].id
    : null
  )

  # Port range is irrelevant for ip_protocol = "-1" (all traffic).
  from_port   = local.rules_by_id[each.value.rule_id].protocol != "-1" ? local.rules_by_id[each.value.rule_id].from_port : null
  to_port     = local.rules_by_id[each.value.rule_id].protocol != "-1" ? local.rules_by_id[each.value.rule_id].to_port : null
  ip_protocol = local.rules_by_id[each.value.rule_id].protocol

  description = each.value.description

  tags = merge(
    var.common_tags,
    {
      Name = "${each.value.source}-${each.value.rule_id}"
    }
  )

  depends_on = [aws_security_group.kr_security_group]
}
