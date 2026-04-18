#!/usr/bin/env bash
# =============================================================================
# rules-vars.sh
# Generates core/variables/security.auto.tfvars from environment YAML sources.
#
# Sourced by replace-vars.sh — expects the following to already be set:
#   RULES_YAML  – path to environment/<ENV>/platform/rules.yml
#   OUT_DIR     – path to core/variables/
#   _sub()      – token substitution helper from replace-vars.sh
# =============================================================================

echo "── rules-vars.sh: generating security.auto.tfvars ──────────────────────"

# Helper: renders a list of SG rule objects from a yq path into HCL list syntax.
# Usage: _render_sg_rules <yaml_file> <yq_path>
_render_sg_rules() {
  local yaml_file="$1"
  local yq_path="$2"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local desc proto fp tp
    desc="$(yq "${yq_path}[${i}].description" "${yaml_file}")"
    proto="$(yq "${yq_path}[${i}].protocol" "${yaml_file}")"
    fp="$(yq "${yq_path}[${i}].from_port" "${yaml_file}")"
    tp="$(yq "${yq_path}[${i}].to_port" "${yaml_file}")"

    # Build cidr_blocks list
    local cb_count cidr_hcl
    cb_count="$(yq "${yq_path}[${i}].cidr_blocks | length" "${yaml_file}")"
    cidr_hcl="["
    for j in $(seq 0 1 $((cb_count - 1))); do
      local cidr
      cidr="$(yq "${yq_path}[${i}].cidr_blocks[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && cidr_hcl+=", "
      cidr_hcl+="\"${cidr}\""
    done
    cidr_hcl+="]"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { description = \"${desc}\", protocol = \"${proto}\", from_port = ${fp}, to_port = ${tp}, cidr_blocks = ${cidr_hcl} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders NACL rules from a yq path into HCL list syntax.
# Usage: _render_nacl_rules <yaml_file> <yq_path>
_render_nacl_rules() {
  local yaml_file="$1"
  local yq_path="$2"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local rn proto action cidr fp tp
    rn="$(yq "${yq_path}[${i}].rule_number" "${yaml_file}")"
    proto="$(yq "${yq_path}[${i}].protocol" "${yaml_file}")"
    action="$(yq "${yq_path}[${i}].action" "${yaml_file}")"
    cidr="$(yq "${yq_path}[${i}].cidr_block" "${yaml_file}")"
    fp="$(yq "${yq_path}[${i}].from_port" "${yaml_file}")"
    tp="$(yq "${yq_path}[${i}].to_port" "${yaml_file}")"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { rule_number = ${rn}, protocol = \"${proto}\", action = \"${action}\", cidr_block = \"${cidr}\", from_port = ${fp}, to_port = ${tp} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

SG_INGRESS="$(_render_sg_rules "${RULES_YAML}" '.security_groups.ingress')"
SG_EGRESS="$(_render_sg_rules "${RULES_YAML}"  '.security_groups.egress')"
NACL_PRI_IN="$(_render_nacl_rules  "${RULES_YAML}" '.nacl.private.inbound')"
NACL_PRI_OUT="$(_render_nacl_rules "${RULES_YAML}" '.nacl.private.outbound')"
NACL_PUB_IN="$(_render_nacl_rules  "${RULES_YAML}" '.nacl.public.inbound')"
NACL_PUB_OUT="$(_render_nacl_rules "${RULES_YAML}" '.nacl.public.outbound')"

# ── Write security.auto.tfvars from master template ──────────────────────────
SEC_DEST="${OUT_DIR}/security.auto.tfvars"
cp "${OUT_DIR}/security.auto.tfvars.tpl" "${SEC_DEST}"

_sub "${SEC_DEST}" "REPLACE_SG_INGRESS"            "${SG_INGRESS}"
_sub "${SEC_DEST}" "REPLACE_SG_EGRESS"             "${SG_EGRESS}"
_sub "${SEC_DEST}" "REPLACE_NACL_PRIVATE_INBOUND"  "${NACL_PRI_IN}"
_sub "${SEC_DEST}" "REPLACE_NACL_PRIVATE_OUTBOUND" "${NACL_PRI_OUT}"
_sub "${SEC_DEST}" "REPLACE_NACL_PUBLIC_INBOUND"   "${NACL_PUB_IN}"
_sub "${SEC_DEST}" "REPLACE_NACL_PUBLIC_OUTBOUND"  "${NACL_PUB_OUT}"
echo "Written: ${SEC_DEST}"
