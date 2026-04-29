# =============================================================================
# core/variables/rules.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Sources:
#   environment/<ENV>/platform/rules.yml  → SG zones, links, rules, and NACL rules
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

security_groups_zone = REPLACE_SG_ZONES

security_group_rule_link = REPLACE_SG_RULE_LINKS

security_group_rules = REPLACE_SG_RULES

nacl_inbound_rules  = REPLACE_NACL_PRIVATE_INBOUND

nacl_outbound_rules = REPLACE_NACL_PRIVATE_OUTBOUND

nacl_public_inbound_rules  = REPLACE_NACL_PUBLIC_INBOUND

nacl_public_outbound_rules = REPLACE_NACL_PUBLIC_OUTBOUND
