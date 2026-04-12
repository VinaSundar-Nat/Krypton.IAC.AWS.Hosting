# =============================================================================
# core/variables/security.auto.tfvars — MASTER TEMPLATE
#
# REPLACE_* tokens are substituted by scripts/replace-vars.sh at runtime.
# Restored to this state by scripts/revert-master-vars.sh after terraform runs.
#
# Sources:
#   environment/<ENV>/security/rules.yaml   → SG and NACL rules
#   environment/<ENV>/security/network.yaml → subnet types drive NACL scope
#
# DO NOT edit REPLACE_* tokens — edit the source YAML files instead.
# =============================================================================

sg_ingress_rules = REPLACE_SG_INGRESS

sg_egress_rules = REPLACE_SG_EGRESS

nacl_inbound_rules  = REPLACE_NACL_PRIVATE_INBOUND

nacl_outbound_rules = REPLACE_NACL_PRIVATE_OUTBOUND

nacl_public_inbound_rules  = REPLACE_NACL_PUBLIC_INBOUND

nacl_public_outbound_rules = REPLACE_NACL_PUBLIC_OUTBOUND
