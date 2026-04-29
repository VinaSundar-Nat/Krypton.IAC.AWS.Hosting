#!/usr/bin/env bash
# =============================================================================
# rules-vars.sh
# Generates core/variables/rules.auto.tfvars from environment YAML sources.
#
# Sourced by replace-vars.sh — expects the following to already be set:
#   SID         – service identifier (e.g. kr-carevo)
#   RULES_YAML  – path to environment/<ENV>/platform/rules.yml
#   OUT_DIR     – path to core/variables/
#   _sub()      – token substitution helper from replace-vars.sh
# =============================================================================

echo "── rules-vars.sh: generating rules.auto.tfvars ──────────────────────────"

# yq selector: pick the component matching the given SID
SEL='.component[] | select(.sid == "'"${SID}"'")'

# Helper: renders security_groups_zone list into HCL list syntax.
_render_sg_zones() {
  local yaml_file="$1"
  local yq_path="${SEL} | .security_group.security_groups_zone"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local name id enabled desc
    name="$(yq    "${yq_path}[${i}].name"        "${yaml_file}")"
    id="$(yq      "${yq_path}[${i}].id"          "${yaml_file}")"
    enabled="$(yq "${yq_path}[${i}].enabled"     "${yaml_file}")"
    desc="$(yq    "${yq_path}[${i}].description" "${yaml_file}")"
    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${name}\", id = \"${id}\", enabled = ${enabled}, description = \"${desc}\" }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders security_group_rule_link list into HCL list syntax.
# rules is a YAML map of rule-id → { cidr_blocks } rendered as an HCL map.
_render_sg_rule_links() {
  local yaml_file="$1"
  local yq_path="${SEL} | .security_group.security_group_rule_link"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local source target desc
    source="$(yq "${yq_path}[${i}].source" "${yaml_file}")"
    target="$(yq "${yq_path}[${i}].target" "${yaml_file}")"
    desc="$(yq   "${yq_path}[${i}].description" "${yaml_file}")"

    # Build rules as HCL map: { in001 = { cidr_blocks = "..." }, ... }
    local rules_hcl first_rule rule_key cidr
    rules_hcl="{"
    first_rule=true
    while IFS= read -r rule_key; do
      [[ -z "${rule_key}" || "${rule_key}" == "null" ]] && continue
      cidr="$(yq "${yq_path}[${i}].rules.\"${rule_key}\".cidr_blocks // \"\"" "${yaml_file}")"
      [[ "${first_rule}" == "true" ]] || rules_hcl+=","
      rules_hcl+=$'\n'"      ${rule_key} = { cidr_blocks = \"${cidr}\" }"
      first_rule=false
    done <<< "$(yq "${yq_path}[${i}].rules | keys | .[]" "${yaml_file}" 2>/dev/null || true)"
    rules_hcl+=$'\n'"    }"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { source = \"${source}\", target = \"${target}\", rules = ${rules_hcl}, description = \"${desc}\" }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders security_group rules list into HCL list syntax.
_render_sg_rules() {
  local yaml_file="$1"
  local yq_path="${SEL} | .security_group.rules"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local id desc proto fp tp type
    id="$(yq    "${yq_path}[${i}].id"          "${yaml_file}")"
    desc="$(yq  "${yq_path}[${i}].description" "${yaml_file}")"
    proto="$(yq "${yq_path}[${i}].protocol"    "${yaml_file}")"
    fp="$(yq    "${yq_path}[${i}].from_port"   "${yaml_file}")"
    tp="$(yq    "${yq_path}[${i}].to_port"     "${yaml_file}")"
    type="$(yq  "${yq_path}[${i}].type"        "${yaml_file}")"
    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { id = \"${id}\", description = \"${desc}\", protocol = \"${proto}\", from_port = ${fp}, to_port = ${tp}, type = \"${type}\" }"
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
    rn="$(yq     "${yq_path}[${i}].rule_number" "${yaml_file}")"
    proto="$(yq  "${yq_path}[${i}].protocol"    "${yaml_file}")"
    action="$(yq "${yq_path}[${i}].action"      "${yaml_file}")"
    cidr="$(yq   "${yq_path}[${i}].cidr_block"  "${yaml_file}")"
    fp="$(yq     "${yq_path}[${i}].from_port"   "${yaml_file}")"
    tp="$(yq     "${yq_path}[${i}].to_port"     "${yaml_file}")"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { rule_number = ${rn}, protocol = \"${proto}\", action = \"${action}\", cidr_block = \"${cidr}\", from_port = ${fp}, to_port = ${tp} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

SG_ZONES="$(_render_sg_zones      "${RULES_YAML}")"
SG_RULE_LINKS="$(_render_sg_rule_links "${RULES_YAML}")"
SG_RULES="$(_render_sg_rules      "${RULES_YAML}")"
NACL_PRI_IN="$(_render_nacl_rules  "${RULES_YAML}" "${SEL} | .nacl.private.inbound")"
NACL_PRI_OUT="$(_render_nacl_rules "${RULES_YAML}" "${SEL} | .nacl.private.outbound")"
NACL_PUB_IN="$(_render_nacl_rules  "${RULES_YAML}" "${SEL} | .nacl.public.inbound")"
NACL_PUB_OUT="$(_render_nacl_rules "${RULES_YAML}" "${SEL} | .nacl.public.outbound")"

# ── Write rules.auto.tfvars from master template ────────────────────────────
SEC_DEST="${OUT_DIR}/rules.auto.tfvars"
cp "${OUT_DIR}/rules.auto.tfvars.tpl" "${SEC_DEST}"

_sub "${SEC_DEST}" "REPLACE_SG_ZONES"              "${SG_ZONES}"
_sub "${SEC_DEST}" "REPLACE_SG_RULE_LINKS"         "${SG_RULE_LINKS}"
_sub "${SEC_DEST}" "REPLACE_SG_RULES"              "${SG_RULES}"
_sub "${SEC_DEST}" "REPLACE_NACL_PRIVATE_INBOUND"  "${NACL_PRI_IN}"
_sub "${SEC_DEST}" "REPLACE_NACL_PRIVATE_OUTBOUND" "${NACL_PRI_OUT}"
_sub "${SEC_DEST}" "REPLACE_NACL_PUBLIC_INBOUND"   "${NACL_PUB_IN}"
_sub "${SEC_DEST}" "REPLACE_NACL_PUBLIC_OUTBOUND"  "${NACL_PUB_OUT}"
echo "Written: ${SEC_DEST}"
