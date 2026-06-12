#!/usr/bin/env bash
# =============================================================================
# identity-vars.sh
# Generates core/variables/identity.auto.tfvars from environment YAML sources.
#
# Sourced by replace-vars.sh — expects the following to already be set:
#   SID             – service identifier (e.g. kr-carevo)
#   IDENTITY_YAML   – path to environment/<ENV>/platform/identity.yml
#   OUT_DIR         – path to core/variables/
#   ORG_NAME        – organisation name
#   PROGRAM_NAME    – program name
#   ENV_NAME        – environment name (dev|stage|prod)
#   _sub()          – token substitution helper from replace-vars.sh
# =============================================================================

echo "── identity-vars.sh: generating identity.auto.tfvars ────────────────────"

# yq selector: pick the component matching the given SID
SEL='.component[] | select(.sid == "'"${SID}"'")'

# Helper: JSON-encode an arbitrary string for embedding as an HCL string literal.
# Reads raw content from stdin and emits a double-quoted JSON-safe string.
_json_str() {
  python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

# ── Global: IAM Policies ──────────────────────────────────────────────────────
# Sourced from identity.yml component.global.policy[].
# template_param is serialised to a compact JSON string (list of statement objects).
_render_iam_policies() {
  local yaml_file="$1"
  local yq_path="${SEL} | .global.policy"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local name desc tmpl_json
    name="$(yq    "${yq_path}[${i}].name"        "${yaml_file}")"
    desc="$(yq    "${yq_path}[${i}].description" "${yaml_file}")"
    tmpl_json="$(yq -o=json "${yq_path}[${i}].template_param" "${yaml_file}" | _json_str)"
    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${name}\", description = \"${desc}\", template_param = ${tmpl_json} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Global: IAM Groups ────────────────────────────────────────────────────────
# Sourced from identity.yml component.global.group[].
_render_iam_groups() {
  local yaml_file="$1"
  local yq_path="${SEL} | .global.group"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local name desc pol_count pol_hcl
    name="$(yq "${yq_path}[${i}].name"        "${yaml_file}")"
    desc="$(yq "${yq_path}[${i}].description" "${yaml_file}")"
    pol_count="$(yq "${yq_path}[${i}].policies | length" "${yaml_file}")"
    pol_hcl="["
    for j in $(seq 0 1 $((pol_count - 1))); do
      local pol
      pol="$(yq "${yq_path}[${i}].policies[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && pol_hcl+=", "
      pol_hcl+="\"${pol}\""
    done
    pol_hcl+="]"
    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${name}\", description = \"${desc}\", policies = ${pol_hcl} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Global: IAM Users ─────────────────────────────────────────────────────────
# Sourced from identity.yml component.global.user[].
_render_iam_users() {
  local yaml_file="$1"
  local yq_path="${SEL} | .global.user"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 1 $((count - 1))); do
    local name enabled desc grp_count grp_hcl
    name="$(yq    "${yq_path}[${i}].name"        "${yaml_file}")"
    enabled="$(yq "${yq_path}[${i}].enabled"     "${yaml_file}")"
    desc="$(yq    "${yq_path}[${i}].description" "${yaml_file}")"
    grp_count="$(yq "${yq_path}[${i}].groups | length" "${yaml_file}")"
    grp_hcl="["
    for j in $(seq 0 1 $((grp_count - 1))); do
      local grp
      grp="$(yq "${yq_path}[${i}].groups[${j}]" "${yaml_file}")"
      [[ $j -gt 0 ]] && grp_hcl+=", "
      grp_hcl+="\"${grp}\""
    done
    grp_hcl+="]"
    [[ $i -gt 0 ]] && hcl+=","
    hcl+=$'\n'"    { name = \"${name}\", enabled = ${enabled}, description = \"${desc}\", groups = ${grp_hcl} }"
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster: IAM Roles ────────────────────────────────────────────────────────
# Collects roles across all cluster entries for the SID.
# assume_role_policy is the JSON-encoded trust relationship document.
_render_cluster_roles() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster"
  local cluster_count
  cluster_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$cluster_count" == "0" || "$cluster_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((cluster_count - 1))); do
    local role_path="${yq_path}[${i}].role"
    local role_count
    role_count="$(yq "${role_path} | length" "${yaml_file}")"
    [[ "$role_count" == "0" || "$role_count" == "null" ]] && continue
    for j in $(seq 0 1 $((role_count - 1))); do
      local name desc trust_json
      name="$(yq        "${role_path}[${j}].name"        "${yaml_file}")"
      desc="$(yq        "${role_path}[${j}].description" "${yaml_file}")"
      trust_json="$(yq -o=json "${role_path}[${j}].json" "${yaml_file}" | _json_str)"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { name = \"${name}\", description = \"${desc}\", assume_role_policy = ${trust_json} }"
      first=false
    done
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster: IAM Policies (managed policy attachments) ───────────────────────
# Collects policy entries across all cluster entries for the SID.
_render_cluster_policies() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster"
  local cluster_count
  cluster_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$cluster_count" == "0" || "$cluster_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((cluster_count - 1))); do
    local pol_path="${yq_path}[${i}].policy"
    local pol_count
    pol_count="$(yq "${pol_path} | length" "${yaml_file}")"
    [[ "$pol_count" == "0" || "$pol_count" == "null" ]] && continue
    for j in $(seq 0 1 $((pol_count - 1))); do
      local name enabled desc arn_count arn_hcl role_count role_hcl
      name="$(yq    "${pol_path}[${j}].name"        "${yaml_file}")"
      enabled="$(yq "${pol_path}[${j}].enabled"     "${yaml_file}")"
      desc="$(yq    "${pol_path}[${j}].description" "${yaml_file}")"
      arn_count="$(yq "${pol_path}[${j}].arns | length" "${yaml_file}")"
      arn_hcl="["
      for k in $(seq 0 1 $((arn_count - 1))); do
        local arn
        arn="$(yq "${pol_path}[${j}].arns[${k}]" "${yaml_file}")"
        [[ $k -gt 0 ]] && arn_hcl+=", "
        arn_hcl+="\"${arn}\""
      done
      arn_hcl+="]"
      role_count="$(yq "${pol_path}[${j}].roles | length" "${yaml_file}")"
      role_hcl="["
      for k in $(seq 0 1 $((role_count - 1))); do
        local role
        role="$(yq "${pol_path}[${j}].roles[${k}]" "${yaml_file}")"
        [[ $k -gt 0 ]] && role_hcl+=", "
        role_hcl+="\"${role}\""
      done
      role_hcl+="]"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { name = \"${name}\", enabled = ${enabled}, description = \"${desc}\", arns = ${arn_hcl}, roles = ${role_hcl} }"
      first=false
    done
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Nodegroup: IAM Roles ──────────────────────────────────────────────────────
# Collects roles across all nodegroup entries for the SID.
_render_nodegroup_roles() {
  local yaml_file="$1"
  local yq_path="${SEL} | .nodegroup"
  local ng_count
  ng_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ng_count" == "0" || "$ng_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((ng_count - 1))); do
    local role_path="${yq_path}[${i}].role"
    local role_count
    role_count="$(yq "${role_path} | length" "${yaml_file}")"
    [[ "$role_count" == "0" || "$role_count" == "null" ]] && continue
    for j in $(seq 0 1 $((role_count - 1))); do
      local name desc trust_json
      name="$(yq        "${role_path}[${j}].name"        "${yaml_file}")"
      desc="$(yq        "${role_path}[${j}].description" "${yaml_file}")"
      trust_json="$(yq -o=json "${role_path}[${j}].json" "${yaml_file}" | _json_str)"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { name = \"${name}\", description = \"${desc}\", assume_role_policy = ${trust_json} }"
      first=false
    done
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Nodegroup: IAM Policies (managed policy attachments) ─────────────────────
# Collects policy entries across all nodegroup entries for the SID.
_render_nodegroup_policies() {
  local yaml_file="$1"
  local yq_path="${SEL} | .nodegroup"
  local ng_count
  ng_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ng_count" == "0" || "$ng_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((ng_count - 1))); do
    local pol_path="${yq_path}[${i}].policy"
    local pol_count
    pol_count="$(yq "${pol_path} | length" "${yaml_file}")"
    [[ "$pol_count" == "0" || "$pol_count" == "null" ]] && continue
    for j in $(seq 0 1 $((pol_count - 1))); do
      local name enabled desc arn_count arn_hcl role_count role_hcl
      name="$(yq    "${pol_path}[${j}].name"        "${yaml_file}")"
      enabled="$(yq "${pol_path}[${j}].enabled"     "${yaml_file}")"
      desc="$(yq    "${pol_path}[${j}].description" "${yaml_file}")"
      arn_count="$(yq "${pol_path}[${j}].arns | length" "${yaml_file}")"
      arn_hcl="["
      for k in $(seq 0 1 $((arn_count - 1))); do
        local arn
        arn="$(yq "${pol_path}[${j}].arns[${k}]" "${yaml_file}")"
        [[ $k -gt 0 ]] && arn_hcl+=", "
        arn_hcl+="\"${arn}\""
      done
      arn_hcl+="]"
      role_count="$(yq "${pol_path}[${j}].roles | length" "${yaml_file}")"
      role_hcl="["
      for k in $(seq 0 1 $((role_count - 1))); do
        local role
        role="$(yq "${pol_path}[${j}].roles[${k}]" "${yaml_file}")"
        [[ $k -gt 0 ]] && role_hcl+=", "
        role_hcl+="\"${role}\""
      done
      role_hcl+="]"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { name = \"${name}\", enabled = ${enabled}, description = \"${desc}\", arns = ${arn_hcl}, roles = ${role_hcl} }"
      first=false
    done
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster: Access Entries ───────────────────────────────────────────────────
# Collects access entries across all cluster entries for the SID.
# Each entry grants an IAM principal (role/user) Kubernetes API access.
# Sourced from identity.yml component.cluster[].access[].
# Extracts role_name from access entries; Terraform constructs principal_arn using
# the running user's AWS account ID via data.aws_caller_identity.
_render_cluster_access() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster"
  local cluster_count
  cluster_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$cluster_count" == "0" || "$cluster_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((cluster_count - 1))); do
    local cluster_name access_path access_count
    cluster_name="$(yq "${yq_path}[${i}].name" "${yaml_file}")"
    access_path="${yq_path}[${i}].access"
    access_count="$(yq "${access_path} | length" "${yaml_file}")"
    [[ "$access_count" == "0" || "$access_count" == "null" ]] && continue
    for j in $(seq 0 1 $((access_count - 1))); do
      local role_name desc policy_arn access_scope
      role_name="$(yq "${access_path}[${j}].role_name" "${yaml_file}")"
      desc="$(yq      "${access_path}[${j}].description"   "${yaml_file}")"
      policy_arn="$(yq    "${access_path}[${j}].policy_arn"    "${yaml_file}")"
      access_scope="$(yq  "${access_path}[${j}].access_scope"  "${yaml_file}")"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { cluster_name = \"${cluster_name}\", role_name = \"${role_name}\", description = \"${desc}\", policy_arn = \"${policy_arn}\", access_scope = \"${access_scope}\" }"
      first=false
    done
  done
  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster Identity: Roles ──────────────────────────────────────────────────
# Sourced from identity.yml component.cluster_identity[].roles[].
_render_cluster_identity_roles() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster_identity"
  local ci_count
  ci_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ci_count" == "0" || "$ci_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((ci_count - 1))); do
    local cluster_name roles_path role_count
    cluster_name="$(yq "${yq_path}[${i}].cluster" "${yaml_file}")"
    roles_path="${yq_path}[${i}].roles"
    role_count="$(yq "${roles_path} | length" "${yaml_file}")"
    [[ "$role_count" == "0" || "$role_count" == "null" ]] && continue

    for j in $(seq 0 1 $((role_count - 1))); do
      local name sid desc version effect action_count actions_hcl principal_count principals_hcl
      name="$(yq "${roles_path}[${j}].name" "${yaml_file}")"
      sid="$(yq "${roles_path}[${j}].sid" "${yaml_file}")"
      desc="$(yq "${roles_path}[${j}].description" "${yaml_file}")"
      version="$(yq "${roles_path}[${j}].template.version" "${yaml_file}")"
      effect="$(yq "${roles_path}[${j}].template.Effect" "${yaml_file}")"

      action_count="$(yq "${roles_path}[${j}].template.Action | length" "${yaml_file}")"
      actions_hcl="["
      for k in $(seq 0 1 $((action_count - 1))); do
        local action
        action="$(yq "${roles_path}[${j}].template.Action[${k}]" "${yaml_file}")"
        [[ $k -gt 0 ]] && actions_hcl+=", "
        actions_hcl+="\"${action}\""
      done
      actions_hcl+="]"

      # Render principals as a list of { type, value } objects
      principal_count="$(yq "${roles_path}[${j}].template.Principal | length" "${yaml_file}")"
      principals_hcl="["
      for k in $(seq 0 1 $((principal_count - 1))); do
        local p_type p_value
        p_type="$(yq "${roles_path}[${j}].template.Principal[${k}].type" "${yaml_file}")"
        p_value="$(yq "${roles_path}[${j}].template.Principal[${k}].value" "${yaml_file}")"
        [[ $k -gt 0 ]] && principals_hcl+=", "
        principals_hcl+="{ type = \"${p_type}\", value = \"${p_value}\" }"
      done
      principals_hcl+="]"

      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { cluster_name = \"${cluster_name}\", name = \"${name}\", sid = \"${sid}\", description = \"${desc}\", version = \"${version}\", effect = \"${effect}\", actions = ${actions_hcl}, principals = ${principals_hcl} }"
      first=false
    done
  done

  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster Identity: Groups ─────────────────────────────────────────────────
# Sourced from identity.yml component.cluster_identity[].groups[].
_render_cluster_identity_groups() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster_identity"
  local ci_count
  ci_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ci_count" == "0" || "$ci_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((ci_count - 1))); do
    local cluster_name groups_path group_count
    cluster_name="$(yq "${yq_path}[${i}].cluster" "${yaml_file}")"
    groups_path="${yq_path}[${i}].groups"
    group_count="$(yq "${groups_path} | length" "${yaml_file}")"
    [[ "$group_count" == "0" || "$group_count" == "null" ]] && continue

    for j in $(seq 0 1 $((group_count - 1))); do
      local name assume_role
      name="$(yq "${groups_path}[${j}].name" "${yaml_file}")"
      assume_role="$(yq "${groups_path}[${j}].assume_role" "${yaml_file}")"
      [[ "${first}" == "true" ]] || hcl+=","
      hcl+=$'\n'"    { cluster_name = \"${cluster_name}\", name = \"${name}\", assume_role = \"${assume_role}\" }"
      first=false
    done
  done

  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Cluster Identity: Users ──────────────────────────────────────────────────
# Sourced from identity.yml component.cluster_identity[].groups[].users[].
_render_cluster_identity_users() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster_identity"
  local ci_count
  ci_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ci_count" == "0" || "$ci_count" == "null" ]] && echo "[]" && return

  local hcl="["
  local first=true
  for i in $(seq 0 1 $((ci_count - 1))); do
    local cluster_name groups_path group_count
    cluster_name="$(yq "${yq_path}[${i}].cluster" "${yaml_file}")"
    groups_path="${yq_path}[${i}].groups"
    group_count="$(yq "${groups_path} | length" "${yaml_file}")"
    [[ "$group_count" == "0" || "$group_count" == "null" ]] && continue

    for j in $(seq 0 1 $((group_count - 1))); do
      local group_name users_path user_count
      group_name="$(yq "${groups_path}[${j}].name" "${yaml_file}")"
      users_path="${groups_path}[${j}].users"
      user_count="$(yq "${users_path} | length" "${yaml_file}")"
      [[ "$user_count" == "0" || "$user_count" == "null" ]] && continue

      for k in $(seq 0 1 $((user_count - 1))); do
        local name enabled force_destroy namespace policy_arn desc k8_count k8_hcl
        name="$(yq "${users_path}[${k}].name" "${yaml_file}")"
        enabled="$(yq "${users_path}[${k}].enabled" "${yaml_file}")"
        force_destroy="$(yq "${users_path}[${k}].force_destroy" "${yaml_file}")"
        namespace="$(yq "${users_path}[${k}].namespace" "${yaml_file}")"
        policy_arn="$(yq "${users_path}[${k}].policy_arn" "${yaml_file}")"
        desc="$(yq "${users_path}[${k}].description" "${yaml_file}")"

        # k8group defaults to system:masters when not defined.
        k8_count="$(yq "${users_path}[${k}].k8group // [] | length" "${yaml_file}")"
        k8_hcl="["
        if [[ "$k8_count" == "0" || "$k8_count" == "null" ]]; then
          k8_hcl+="\"system:masters\""
        else
          for m in $(seq 0 1 $((k8_count - 1))); do
            local k8_group
            k8_group="$(yq "${users_path}[${k}].k8group[${m}]" "${yaml_file}")"
            [[ $m -gt 0 ]] && k8_hcl+=", "
            k8_hcl+="\"${k8_group}\""
          done
        fi
        k8_hcl+="]"

        [[ "${first}" == "true" ]] || hcl+=","
        hcl+=$'\n'"    { cluster_name = \"${cluster_name}\", group_name = \"${group_name}\", name = \"${name}\", enabled = ${enabled}, force_destroy = ${force_destroy}, namespace = \"${namespace}\", policy_arn = \"${policy_arn}\", k8group = ${k8_hcl}, description = \"${desc}\" }"
        first=false
      done
    done
  done

  hcl+=$'\n'"  ]"
  echo "${hcl}"
}

# ── Pod Identity ─────────────────────────────────────────────────────────────
# Sourced from identity.yml component.cluster_identity[].pod_identity.
# Cross-references cluster_identity[].roles[] to resolve role names from sids.
_render_pod_identity() {
  local yaml_file="$1"
  local yq_path="${SEL} | .cluster_identity"
  local ci_count
  ci_count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$ci_count" == "0" || "$ci_count" == "null" ]] \
    && echo '{ required = false, cluster_name = "", roles = [] }' && return

  # Use first cluster_identity block
  local cluster_name pi_path
  cluster_name="$(yq "${yq_path}[0].cluster" "${yaml_file}")"
  pi_path="${yq_path}[0].pod_identity"

  local required
  required="$(yq "${pi_path}.required" "${yaml_file}")"
  [[ -z "$required" || "$required" == "null" ]] && required="false"

  local role_count
  role_count="$(yq "${pi_path}.roles | length" "${yaml_file}")"
  if [[ "$role_count" == "0" || "$role_count" == "null" ]]; then
    echo "{ required = ${required}, cluster_name = \"${cluster_name}\", roles = [] }"
    return
  fi

  local roles_hcl="["
  local first=true
  for i in $(seq 0 1 $((role_count - 1))); do
    local role_sid role_name desc sa_name sa_ns pol_count pol_hcl

    role_sid="$(yq "${pi_path}.roles[${i}].role" "${yaml_file}")"
    desc="$(yq "${pi_path}.roles[${i}].description" "${yaml_file}")"
    sa_name="$(yq "${pi_path}.roles[${i}].service_account.name" "${yaml_file}")"
    sa_ns="$(yq "${pi_path}.roles[${i}].service_account.namespace" "${yaml_file}")"

    # Resolve full role name from cluster_identity[].roles[] matching the sid
    role_name="$(yq "${yq_path}[0].roles[] | select(.sid == \"${role_sid}\") | .name" "${yaml_file}")"
    [[ -z "$role_name" || "$role_name" == "null" ]] && role_name=""

    # Build policy list
    pol_count="$(yq "${pi_path}.roles[${i}].policy | length" "${yaml_file}")"
    pol_hcl="["
    for j in $(seq 0 1 $((pol_count - 1))); do
      local tmpl_loc pol_name
      tmpl_loc="$(yq "${pi_path}.roles[${i}].policy[${j}].template_location" "${yaml_file}")"
      pol_name="$(yq "${pi_path}.roles[${i}].policy[${j}].name" "${yaml_file}")"
      [[ $j -gt 0 ]] && pol_hcl+=", "
      pol_hcl+="{ template_location = \"${tmpl_loc}\", name = \"${pol_name}\" }"
    done
    pol_hcl+="]"

    [[ "${first}" == "true" ]] || roles_hcl+=","
    roles_hcl+=$'\n'"    { role = \"${role_sid}\", role_name = \"${role_name}\", description = \"${desc}\", policy = ${pol_hcl}, service_account = { name = \"${sa_name}\", namespace = \"${sa_ns}\" } }"
    first=false
  done
  roles_hcl+=$'\n'"  ]"

  echo "{ required = ${required}, cluster_name = \"${cluster_name}\", roles = ${roles_hcl} }"
}

IAM_POLICIES="$(_render_iam_policies         "${IDENTITY_YAML}")"
IAM_GROUPS="$(_render_iam_groups             "${IDENTITY_YAML}")"
IAM_USERS="$(_render_iam_users               "${IDENTITY_YAML}")"
CLUSTER_ROLES="$(_render_cluster_roles       "${IDENTITY_YAML}")"
CLUSTER_POLICIES="$(_render_cluster_policies "${IDENTITY_YAML}")"
NODEGROUP_ROLES="$(_render_nodegroup_roles   "${IDENTITY_YAML}")"
NODEGROUP_POLICIES="$(_render_nodegroup_policies "${IDENTITY_YAML}")"
CLUSTER_ACCESS="$(_render_cluster_access     "${IDENTITY_YAML}")"
CLUSTER_IDENTITY_ROLES="$(_render_cluster_identity_roles   "${IDENTITY_YAML}")"
CLUSTER_IDENTITY_GROUPS="$(_render_cluster_identity_groups "${IDENTITY_YAML}")"
CLUSTER_IDENTITY_USERS="$(_render_cluster_identity_users   "${IDENTITY_YAML}")"
POD_IDENTITY="$(_render_pod_identity "${IDENTITY_YAML}")"

# ── Write identity.auto.tfvars from master template ───────────────────────────
ID_DEST="${OUT_DIR}/identity.auto.tfvars"
cp "${OUT_DIR}/identity.auto.tfvars.tpl" "${ID_DEST}"

_sub "${ID_DEST}" "REPLACE_IAM_POLICIES"       "${IAM_POLICIES}"
_sub "${ID_DEST}" "REPLACE_IAM_GROUPS"         "${IAM_GROUPS}"
_sub "${ID_DEST}" "REPLACE_IAM_USERS"          "${IAM_USERS}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_ROLES"      "${CLUSTER_ROLES}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_POLICIES"   "${CLUSTER_POLICIES}"
_sub "${ID_DEST}" "REPLACE_NODEGROUP_ROLES"    "${NODEGROUP_ROLES}"
_sub "${ID_DEST}" "REPLACE_NODEGROUP_POLICIES" "${NODEGROUP_POLICIES}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_ACCESS"    "${CLUSTER_ACCESS}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_IDENTITY_ROLES"  "${CLUSTER_IDENTITY_ROLES}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_IDENTITY_GROUPS" "${CLUSTER_IDENTITY_GROUPS}"
_sub "${ID_DEST}" "REPLACE_CLUSTER_IDENTITY_USERS"  "${CLUSTER_IDENTITY_USERS}"
_sub "${ID_DEST}" "REPLACE_POD_IDENTITY"            "${POD_IDENTITY}"
echo "Written: ${ID_DEST}"
