#!/usr/bin/env bash
# =============================================================================
# k8hosting-vars.sh
# Generates core/variables/k8hosting.auto.tfvars from environment YAML sources.
#
# Sourced by replace-vars.sh — expects the following to already be set:
#   SID              – service identifier (e.g. kr-carevo)
#   K8HOSTING_YAML   – path to environment/<ENV>/hosting/k8surface.yml
#   OUT_DIR          – path to core/variables/
#   _sub()           – token substitution helper from replace-vars.sh
# =============================================================================

echo "── k8hosting-vars.sh: generating k8hosting.auto.tfvars ─────────────────────"

# yq selector: pick the component matching the given SID
SEL='.component[] | select(.sid == "'"${SID}"'")'

# Helper: JSON-encode an arbitrary string for embedding as an HCL string literal.
# Reads raw content from stdin and emits a double-quoted JSON-safe string.
_json_str() {
  python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

# Helper: renders tags as HCL map
_render_tags() {
  local yaml_file="$1"
  local yq_path="$2"
  local tag_count
  tag_count="$(yq "${yq_path} | length" "${yaml_file}" 2>/dev/null || echo 0)"
  [[ "$tag_count" == "0" || "$tag_count" == "null" ]] && echo "{}" && return

  local hcl="{"
  local first=true
  while IFS= read -r key; do
    [[ -z "$key" || "$key" == "null" ]] && continue
    local val
    val="$(yq "${yq_path}[\"${key}\"]" "${yaml_file}")"
    [[ "${first}" == "true" ]] || hcl+=","
    hcl+=$'\n'"    ${key} = \"${val}\""
    first=false
  done <<< "$(yq "${yq_path} | keys | .[]" "${yaml_file}" 2>/dev/null || true)"
  hcl+=$'\n'"  }"
  echo "${hcl}"
}

# Helper: renders block_device_mappings as HCL object
_render_bdm() {
  local yaml_file="$1"
  local yq_path="$2"
  local device_name
  local type
  local vol_size
  local vol_type
  local del_term
  local encrypted

  device_name="$(yq "${yq_path}.device_name" "${yaml_file}")"
  type="$(yq "${yq_path}.type" "${yaml_file}")"
  vol_size="$(yq "${yq_path}.volume_size" "${yaml_file}")"
  vol_type="$(yq "${yq_path}.volume_type" "${yaml_file}")"
  del_term="$(yq "${yq_path}.delete_on_termination" "${yaml_file}")"
  encrypted="$(yq "${yq_path}.encrypted" "${yaml_file}")"

  echo "{ device_name = \"${device_name}\", type = \"${type}\", volume_size = ${vol_size}, volume_type = \"${vol_type}\", delete_on_termination = ${del_term}, encrypted = ${encrypted} }"
}

# Helper: renders monitoring as HCL object
_render_monitoring() {
  local yaml_file="$1"
  local yq_path="$2"
  local enabled
  enabled="$(yq "${yq_path}.enabled" "${yaml_file}")"
  echo "{ enabled = ${enabled} }"
}

# Helper: renders lifecycle as HCL object
_render_lifecycle() {
  local yaml_file="$1"
  local yq_path="$2"
  local cbd
  cbd="$(yq "${yq_path}.create_before_destroy" "${yaml_file}")"
  echo "{ create_before_destroy = ${cbd} }"
}

# Helper: renders machine config as HCL object
_render_machine() {
  local yaml_file="$1"
  local yq_path="$2"
  local it_count
  local amt
  local ct

  amt="$(yq "${yq_path}.ami_type" "${yaml_file}")"
  ct="$(yq "${yq_path}.capacity_type" "${yaml_file}")"
  
  # Build instance_types list
  it_count="$(yq "${yq_path}.instance_types | length" "${yaml_file}")"
  local it_hcl="["
  for k in $(seq 0 1 $((it_count - 1))); do
    local it
    it="$(yq "${yq_path}.instance_types[${k}]" "${yaml_file}")"
    [[ $k -gt 0 ]] && it_hcl+=", "
    it_hcl+="\"${it}\""
  done
  it_hcl+="]"

  echo "{ instance_types = ${it_hcl}, ami_type = \"${amt}\", capacity_type = \"${ct}\" }"
}

# Helper: renders scaling_config as HCL object
_render_scaling() {
  local yaml_file="$1"
  local yq_path="$2"
  local des
  local max
  local min

  des="$(yq "${yq_path}.desired_size" "${yaml_file}")"
  max="$(yq "${yq_path}.max_size" "${yaml_file}")"
  min="$(yq "${yq_path}.min_size" "${yaml_file}")"

  echo "{ desired_size = ${des}, max_size = ${max}, min_size = ${min} }"
}

# Helper: renders template_parameters as HCL object
_render_template_params() {
  local yaml_file="$1"
  local yq_path="$2"
  local name
  local name_prefix
  local desc
  local sg_count
  local sg_hcl

  name="$(yq "${yq_path}.name" "${yaml_file}")"
  name_prefix="$(yq "${yq_path}.name_prefix" "${yaml_file}")"
  desc="$(yq "${yq_path}.description" "${yaml_file}")"
  
  # Build security_groups list
  sg_count="$(yq "${yq_path}.security_groups | length" "${yaml_file}")"
  sg_hcl="["
  for k in $(seq 0 1 $((sg_count - 1))); do
    local sg
    sg="$(yq "${yq_path}.security_groups[${k}]" "${yaml_file}")"
    [[ $k -gt 0 ]] && sg_hcl+=", "
    sg_hcl+="\"${sg}\""
  done
  sg_hcl+="]"

  local bdm monitoring lifecycle tags
  bdm="$(_render_bdm "${yaml_file}" "${yq_path}.block_device_mappings")"
  monitoring="$(_render_monitoring "${yaml_file}" "${yq_path}.monitoring")"
  lifecycle="$(_render_lifecycle "${yaml_file}" "${yq_path}.lifecycle")"
  tags="$(_render_tags "${yaml_file}" "${yq_path}.tags")"

  echo "{ name = \"${name}\", name_prefix = \"${name_prefix}\", description = \"${desc}\", security_groups = ${sg_hcl}, block_device_mappings = ${bdm}, monitoring = ${monitoring}, lifecycle = ${lifecycle}, tags = ${tags} }"
}

# Helper: renders nodegroup array as HCL
_render_nodegroups() {
  local yaml_file="$1"
  local yq_path="$2"
  local ng_count
  ng_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ng_count" == "0" || "$ng_count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((ng_count - 1))); do
    local ng_path="${yq_path}[${i}]"
    local ng_name ng_desc ng_role ng_template ng_subnets
    local ng_template_params ng_machine ng_scaling

    ng_name="$(yq "${ng_path}.name" "${yaml_file}")"
    ng_desc="$(yq "${ng_path}.description" "${yaml_file}")"
    ng_role="$(yq "${ng_path}.role" "${yaml_file}")"
    ng_template="$(yq "${ng_path}.template" "${yaml_file}")"
    
    # Build subnets list
    local sub_count
    sub_count="$(yq "${ng_path}.subnets | length" "${yaml_file}")"
    local sub_hcl="["
    for j in $(seq 0 1 $((sub_count - 1))); do
      local sub
      sub="$(yq "${ng_path}.subnets[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && sub_hcl+=", "
      sub_hcl+="\"${sub}\""
    done
    sub_hcl+="]"

    ng_template_params="$(_render_template_params "${yaml_file}" "${ng_path}.template_parameters")"
    ng_machine="$(_render_machine "${yaml_file}" "${ng_path}.machine")"
    ng_scaling="$(_render_scaling "${yaml_file}" "${ng_path}.scaling_config")"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${ng_name}\", description = \"${ng_desc}\", role = \"${ng_role}\", template = \"${ng_template}\", subnets = ${sub_hcl}, template_parameters = ${ng_template_params}, machine = ${ng_machine}, scaling_config = ${ng_scaling} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Helper: renders EKS clusters as HCL list with nested nodegroups
_render_eks_clusters() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster"
  local cluster_count
  cluster_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$cluster_count" == "0" || "$cluster_count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((cluster_count - 1))); do
    local c_path="${yq_path}[${i}]"
    local c_name c_role c_version c_ep_pub c_ep_priv
    local c_subnets_count c_subnets_hcl
    local c_sg_count c_sg_hcl
    local c_nodegroups

    c_name="$(yq "${c_path}.name" "${yaml_file}")"
    c_role="$(yq "${c_path}.role" "${yaml_file}")"
    c_version="$(yq "${c_path}.version" "${yaml_file}")"
    c_mode="$(yq "${c_path}.mode" "${yaml_file}")"
    c_ep_pub="$(yq "${c_path}.endpoint_public_access" "${yaml_file}")"
    c_ep_priv="$(yq "${c_path}.endpoint_private_access" "${yaml_file}")"
    
    # Build subnets list
    c_subnets_count="$(yq "${c_path}.subnets | length" "${yaml_file}")"
    c_subnets_hcl="["
    for j in $(seq 0 1 $((c_subnets_count - 1))); do
      local subnet
      subnet="$(yq "${c_path}.subnets[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && c_subnets_hcl+=", "
      c_subnets_hcl+="\"${subnet}\""
    done
    c_subnets_hcl+="]"

    # Build security_groups list
    c_sg_count="$(yq "${c_path}.security_groups | length" "${yaml_file}")"
    c_sg_hcl="["
    for j in $(seq 0 1 $((c_sg_count - 1))); do
      local sg
      sg="$(yq "${c_path}.security_groups[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && c_sg_hcl+=", "
      c_sg_hcl+="\"${sg}\""
    done
    c_sg_hcl+="]"

    # Render nested nodegroups
    c_nodegroups="$(_render_nodegroups "${yaml_file}" "${c_path}.nodegroup")"

    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${c_name}\", role = \"${c_role}\", version = \"${c_version}\", mode = \"${c_mode}\", subnets = ${c_subnets_hcl}, security_groups = ${c_sg_hcl}, endpoint_public_access = ${c_ep_pub}, endpoint_private_access = ${c_ep_priv}, nodegroups = ${c_nodegroups} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# Extract EKS enabled flag from component.opt-in
EKS_ENABLED="$(yq "${SEL} | .opt-in" "${K8HOSTING_YAML}")"
[[ -z "$EKS_ENABLED" || "$EKS_ENABLED" == "null" ]] && EKS_ENABLED="false"

# Render EKS clusters
EKS_CLUSTERS="$(_render_eks_clusters "${K8HOSTING_YAML}")"

# ── Write k8hosting.auto.tfvars from master template ──────────────────────────
K8_DEST="${OUT_DIR}/k8hosting.auto.tfvars"
cp "${OUT_DIR}/k8hosting.auto.tfvars.tpl" "${K8_DEST}"

_sub "${K8_DEST}" "REPLACE_EKS_ENABLED" "${EKS_ENABLED}"
_sub "${K8_DEST}" "REPLACE_EKS_CLUSTERS" "${EKS_CLUSTERS}"
echo "Written: ${K8_DEST}"
