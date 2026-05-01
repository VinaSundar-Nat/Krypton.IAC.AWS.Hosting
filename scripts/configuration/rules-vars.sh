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

# Helper: renders nacl_zone list into HCL list syntax.
_render_nacl_zones() {
  local yaml_file="$1"
  local yq_path="${SEL} | .nacl.nacl_zone"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local name id enabled desc subnets_count subnets_str
    name="$(yq    "${yq_path}[${i}].name"        "${yaml_file}")"
    id="$(yq      "${yq_path}[${i}].id"          "${yaml_file}")"
    enabled="$(yq "${yq_path}[${i}].enabled"     "${yaml_file}")"
    desc="$(yq    "${yq_path}[${i}].description" "${yaml_file}")"

    # Build subnets list
    subnets_count="$(yq "${yq_path}[${i}].subnets | length" "${yaml_file}")"
    subnets_str="["
    if [[ "$subnets_count" != "0" && "$subnets_count" != "null" ]]; then
      for j in $(seq 0 1 $((subnets_count - 1))); do
        local subnet
        subnet="$(yq "${yq_path}[${i}].subnets[${j}]" "${yaml_file}")"
        [[ $j -gt 0 ]] && subnets_str+=", "
        subnets_str+="\"${subnet}\""
      done
    fi
    subnets_str+="]"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${name}\", id = \"${id}\", enabled = ${enabled}, description = \"${desc}\", subnets = ${subnets_str} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders nacl_rule_link list into HCL list syntax.
_render_nacl_rule_links() {
  local yaml_file="$1"
  local yq_path="${SEL} | .nacl.rules_link"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local nacl_id
    nacl_id="$(yq "${yq_path}[${i}].nacl" "${yaml_file}")"

    # Build rules as HCL list of objects
    local rules_hcl rules_count
    rules_count="$(yq "${yq_path}[${i}].rules | length" "${yaml_file}")"
    rules_hcl="["
    
    if [[ "$rules_count" != "0" && "$rules_count" != "null" ]]; then
      for j in $(seq 0 1 $((rules_count - 1))); do
        local rule_id rn desc cidr subnet action
        # Get the first key in this rule object
        rule_id="$(yq "${yq_path}[${i}].rules[${j}] | keys | .[0]" "${yaml_file}")"
        rn="$(yq     "${yq_path}[${i}].rules[${j}].\"${rule_id}\".rule_number" "${yaml_file}")"
        desc="$(yq   "${yq_path}[${i}].rules[${j}].\"${rule_id}\".description"  "${yaml_file}")"
        cidr="$(yq   "${yq_path}[${i}].rules[${j}].\"${rule_id}\".cidr_block"   "${yaml_file}")"
        subnet="$(yq "${yq_path}[${i}].rules[${j}].\"${rule_id}\".subnet"       "${yaml_file}")"
        action="$(yq "${yq_path}[${i}].rules[${j}].\"${rule_id}\".action"       "${yaml_file}")"
        
        [[ $j -gt 0 ]] && rules_hcl+=","
        rules_hcl+=$'\n'"      { \"${rule_id}\" = { rule_number = ${rn}, description = \"${desc}\", cidr_block = \"${cidr}\", subnet = \"${subnet}\", action = \"${action}\" } }"
      done
    fi
    rules_hcl+=$'\n'"    ]"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { nacl = \"${nacl_id}\", rules = ${rules_hcl} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders nacl rules list into HCL list syntax.
_render_nacl_rules() {
  local yaml_file="$1"
  local yq_path="${SEL} | .nacl.rules"
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

SG_ZONES="$(_render_sg_zones          "${RULES_YAML}")"
SG_RULE_LINKS="$(_render_sg_rule_links "${RULES_YAML}")"
SG_RULES="$(_render_sg_rules          "${RULES_YAML}")"
NACL_ZONES="$(_render_nacl_zones       "${RULES_YAML}")"
NACL_RULE_LINKS="$(_render_nacl_rule_links "${RULES_YAML}")"
NACL_RULES="$(_render_nacl_rules       "${RULES_YAML}")"

# ── Write rules.auto.tfvars from master template ────────────────────────────
SEC_DEST="${OUT_DIR}/rules.auto.tfvars"
cp "${OUT_DIR}/rules.auto.tfvars.tpl" "${SEC_DEST}"

_sub "${SEC_DEST}" "REPLACE_SG_ZONES"        "${SG_ZONES}"
_sub "${SEC_DEST}" "REPLACE_SG_RULE_LINKS"   "${SG_RULE_LINKS}"
_sub "${SEC_DEST}" "REPLACE_SG_RULES"        "${SG_RULES}"
_sub "${SEC_DEST}" "REPLACE_NACL_ZONES"      "${NACL_ZONES}"
_sub "${SEC_DEST}" "REPLACE_NACL_RULE_LINKS" "${NACL_RULE_LINKS}"
_sub "${SEC_DEST}" "REPLACE_NACL_RULES"      "${NACL_RULES}"
echo "Written: ${SEC_DEST}"
