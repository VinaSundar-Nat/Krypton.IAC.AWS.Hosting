#!/usr/bin/env bash
# =============================================================================
# replace-vars.sh
# Resolves environment and component settings from a SID (service identifier),
# then generates Terraform variable value files.
#
# Sources:
#   environment/org.yml                      → organisation, program, active env
#   environment/<ENV>/security/network.yaml  → vpc, AZs, NAT  (component by SID)
#   environment/<ENV>/zoning/*.yml            → subnet_zones map
#   environment/<ENV>/security/rules.yaml    → SG and NACL rules
#
# Outputs:
#   core/terraform.tfvars                    → organisation, program, environment tags
#   core/variables/network.auto.tfvars
#   core/variables/security.auto.tfvars
#
# Usage:
#   ./scripts/replace-vars.sh kr-carevo
#   ./scripts/replace-vars.sh kr-otherprog
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SID="${1:?Usage: replace-vars.sh <sid> <env>  e.g. replace-vars.sh kr-carevo dev}"
ENV="${2:?Usage: replace-vars.sh <sid> <env>  e.g. replace-vars.sh kr-carevo dev}"  # extract env name from sid (assumes sid format: kr-<env>)
OUT_DIR="${REPO_ROOT}/core/variables"
TFVARS="${REPO_ROOT}/core/terraform.tfvars"
TFVARS_TPL="${REPO_ROOT}/core/terraform.tfvars.tpl"
ORG_YAML="${REPO_ROOT}/environment/org.yml"

# ── Prerequisite check ────────────────────────────────────────────────────────
if ! command -v yq &>/dev/null; then
  echo "ERROR: yq not found." >&2
  echo "       Install: brew install yq" >&2
  exit 1
fi

if [[ ! -f "${ORG_YAML}" ]]; then
  echo "ERROR: Required file not found: ${ORG_YAML}" >&2
  exit 1
fi

# ── Resolve program / environment from org.yml ───────────────────────────────
ORG_NAME="$(yq '.organisation.name' "${ORG_YAML}")"
PROGRAM_NAME="$(yq '.organisation.program[] | select(.sid == "'"${SID}"'") | .name' "${ORG_YAML}")"
ENV_NAME="${ENV}"

if [[ -z "${PROGRAM_NAME}" || "${PROGRAM_NAME}" == "null" ]]; then
  echo "ERROR: sid '${SID}' not found in ${ORG_YAML}" >&2
  exit 1
fi
if [[ -z "${ENV_NAME}" || "${ENV_NAME}" == "null" ]]; then
  echo "ERROR: tags.environment not set for sid '${SID}' in ${ORG_YAML}" >&2
  exit 1
fi

ENV_DIR="${REPO_ROOT}/environment/${ENV_NAME}"
NET_YAML="${ENV_DIR}/security/network.yaml"
RULES_YAML="${ENV_DIR}/security/rules.yaml"
ZONING_DIR="${ENV_DIR}/zoning"

for f in "${NET_YAML}" "${RULES_YAML}" "${TFVARS_TPL}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required file not found: ${f}" >&2
    exit 1
  fi
done

mkdir -p "${OUT_DIR}"

# ── Substitution helper ───────────────────────────────────────────────────────
# Replaces a REPLACE_TOKEN in DEST file with VALUE in-place.
# Handles multi-line values (SG rules, NACL blocks, HCL maps).
# Usage: _sub DEST TOKEN VALUE
_sub() {
  local dest="$1" token="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  printf '%s' "${value}" > "${tmp}"
  python3 - <<PYEOF
dest  = "${dest}"
token = "${token}"
block = open("${tmp}").read()
content = open(dest).read()
open(dest, "w").write(content.replace(token, block))
PYEOF
  rm -f "${tmp}"
}

echo "── replace-vars.sh: sid=${SID} env=${ENV_NAME} ──────────────────────────"

# =============================================================================
# core/terraform.tfvars — tags (organisation, program, environment)
# =============================================================================
cp "${TFVARS_TPL}" "${TFVARS}"
_sub "${TFVARS}" "REPLACE_ORGANISATION" "${ORG_NAME}"
_sub "${TFVARS}" "REPLACE_PROGRAM"      "${PROGRAM_NAME}"
_sub "${TFVARS}" "REPLACE_ENVIRONMENT"  "${ENV_NAME}"
echo "Written: ${TFVARS}"

# =============================================================================
# network.auto.tfvars
# =============================================================================

# yq selector: pick the component matching the given SID
SEL='.component[] | select(.sid == "'"${SID}"'")'

VPC_NAME="$(yq "${SEL} | .vpc.tags.name" "${NET_YAML}")"
VPC_CIDR="$(yq "${SEL} | .vpc.cidr"  "${NET_YAML}")"
VPC_ENABLE_DNS="$(yq "${SEL} | .vpc.enabledns"  "${NET_YAML}")"
NAT_NAME="$(yq    "${SEL} | .nat_gateway.name"    "${NET_YAML}")"
NAT_ENABLED="$(yq "${SEL} | .nat_gateway.enabled" "${NET_YAML}")"
NAT_SINGLE="$(yq  "${SEL} | .nat_gateway.single"  "${NET_YAML}")"
IGW_NAME="$(yq    "${SEL} | .internet_gateway.name"    "${NET_YAML}")"
IGW_ENABLED="$(yq "${SEL} | .internet_gateway.enabled" "${NET_YAML}")"

# DHCP options — build HCL object
DHCP_ENABLED="$(yq "${SEL} | .dchp_options.enabled"             "${NET_YAML}")"
DHCP_DOMAIN="$(yq  "${SEL} | .dchp_options.domain_name"         "${NET_YAML}")"
DHCP_DNS="$(yq     "${SEL} | .dchp_options.domain_name_servers" "${NET_YAML}")"
DHCP_HCL="{ enabled = ${DHCP_ENABLED}, domain_name = \"${DHCP_DOMAIN}\", domain_name_servers = \"${DHCP_DNS}\" }"

# Build vpc_tags map from network.yaml component.vpc.tags
VPC_TAGS_HCL="{"
while IFS= read -r key; do
  [[ -z "$key" || "$key" == "null" ]] && continue
  val="$(yq "${SEL} | .vpc.tags.${key}" "${NET_YAML}")"
  VPC_TAGS_HCL+=$'\n'"  ${key} = \"${val}\""
done <<< "$(yq "${SEL} | .vpc.tags | keys | .[]" "${NET_YAML}")"
VPC_TAGS_HCL+=$'\n'"}"

# Build AZ list in HCL format: ["us-east-1a", "us-east-1b", ...]
AZ_COUNT="$(yq "${SEL} | .vpc.availability_zones | length" "${NET_YAML}")"
AZS_HCL="["
for i in $(seq 0 $((AZ_COUNT - 1))); do
  AZ="$(yq "${SEL} | .vpc.availability_zones[${i}]" "${NET_YAML}")"
  [[ $i -gt 0 ]] && AZS_HCL+=", "
  AZS_HCL+="\"${AZ}\""
done
AZS_HCL+="]"

# Build subnets list from network.yaml component.subnets[]
SUBNET_COUNT="$(yq "${SEL} | .subnets | length" "${NET_YAML}")"
SUBNETS_HCL="["
for i in $(seq 0 $((SUBNET_COUNT - 1))); do
  SN_NAME="$(yq "${SEL} | .subnets[${i}].name"              "${NET_YAML}")"
  SN_CIDR="$(yq "${SEL} | .subnets[${i}].cidr"              "${NET_YAML}")"
  SN_TYPE="$(yq "${SEL} | .subnets[${i}].type"              "${NET_YAML}")"
  SN_AZ="$(yq   "${SEL} | .subnets[${i}].availability_zone" "${NET_YAML}")"
  [[ $i -gt 0 ]] && SUBNETS_HCL+=","
  SUBNETS_HCL+=$'\n'"  { name = \"${SN_NAME}\", cidr = \"${SN_CIDR}\", type = \"${SN_TYPE}\", availability_zone = \"${SN_AZ}\" }"
done
SUBNETS_HCL+=$'\n'"]"

# Build route_tables list from network.yaml component.route_tables[]
RT_COUNT="$(yq "${SEL} | .route_tables | length" "${NET_YAML}")"
RT_HCL="["
for i in $(seq 0 $((RT_COUNT - 1))); do
  RT_NAME="$(yq "${SEL} | .route_tables[${i}].name" "${NET_YAML}")"
  ROUTE_COUNT="$(yq "${SEL} | .route_tables[${i}].routes | length" "${NET_YAML}")"
  ROUTES_HCL="["
  for j in $(seq 0 $((ROUTE_COUNT - 1))); do
    DEST="$(yq "${SEL} | .route_tables[${i}].routes[${j}].destination" "${NET_YAML}")"
    [[ $j -gt 0 ]] && ROUTES_HCL+=","
    ROUTES_HCL+=" { destination = \"${DEST}\" }"
  done
  ROUTES_HCL+=" ]"
  [[ $i -gt 0 ]] && RT_HCL+=","
  RT_HCL+=$'\n'"  { name = \"${RT_NAME}\", routes = ${ROUTES_HCL} }"
done
RT_HCL+=$'\n'"]"

# Build subnet_zones map from zoning/*.yml files
ZONES_HCL=""
for zone_file in "${ZONING_DIR}"/*.yml "${ZONING_DIR}"/*.yaml; do
  [[ -f "$zone_file" ]] || continue
  ZONE_NAME="$(yq '.zone.name' "${zone_file}" 2>/dev/null || true)"
  [[ -z "${ZONE_NAME}" || "${ZONE_NAME}" == "null" ]] && continue
  ZONE_CIDR="$(yq '.zone.cidr' "${zone_file}")"
  ZONE_PUBLIC="$(yq '.zone.public' "${zone_file}")"
  ZONES_HCL+=$'\n'"  ${ZONE_NAME} = { cidr = \"${ZONE_CIDR}\", public = ${ZONE_PUBLIC} }"
done

# ── Write network.auto.tfvars from master template ────────────────────────────
NET_DEST="${OUT_DIR}/network.auto.tfvars"
cp "${OUT_DIR}/network.auto.tfvars.tpl" "${NET_DEST}"

_sub "${NET_DEST}" "REPLACE_ORGANISATION"       "${ORG_NAME}"
_sub "${NET_DEST}" "REPLACE_PROGRAM"            "${PROGRAM_NAME}"
_sub "${NET_DEST}" "REPLACE_ENVIRONMENT"        "${ENV_NAME}"
_sub "${NET_DEST}" "REPLACE_VPC_NAME"           "${VPC_NAME}"
_sub "${NET_DEST}" "REPLACE_VPC_CIDR"           "${VPC_CIDR}"
_sub "${NET_DEST}" "REPLACE_VPC_ENABLE_DNS"     "${VPC_ENABLE_DNS}"
_sub "${NET_DEST}" "REPLACE_VPC_TAGS"           "${VPC_TAGS_HCL}"
_sub "${NET_DEST}" "REPLACE_AVAILABILITY_ZONES" "${AZS_HCL}"
_sub "${NET_DEST}" "REPLACE_SUBNETS"            "${SUBNETS_HCL}"
_sub "${NET_DEST}" "REPLACE_DHCP_OPTIONS"       "${DHCP_HCL}"
_sub "${NET_DEST}" "REPLACE_NAT_GATEWAY_NAME"   "${NAT_NAME}"
_sub "${NET_DEST}" "REPLACE_NAT_ENABLED"        "${NAT_ENABLED}"
_sub "${NET_DEST}" "REPLACE_NAT_SINGLE"         "${NAT_SINGLE}"
_sub "${NET_DEST}" "REPLACE_IGW_NAME"           "${IGW_NAME}"
_sub "${NET_DEST}" "REPLACE_IGW_ENABLED"        "${IGW_ENABLED}"
_sub "${NET_DEST}" "REPLACE_ROUTE_TABLES"       "${RT_HCL}"
_sub "${NET_DEST}" "REPLACE_SUBNET_ZONES"       "{${ZONES_HCL}}"
echo "Written: ${NET_DEST}"

# =============================================================================
# security.auto.tfvars
# =============================================================================

# Helper: renders a list of rule objects from a yq path into HCL list syntax.
# Usage: _render_sg_rules <yaml_file> <yq_path>
_render_sg_rules() {
  local yaml_file="$1"
  local yq_path="$2"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 $((count - 1))); do
    local desc proto fp tp
    desc="$(yq "${yq_path}[${i}].description" "${yaml_file}")"
    proto="$(yq "${yq_path}[${i}].protocol" "${yaml_file}")"
    fp="$(yq "${yq_path}[${i}].from_port" "${yaml_file}")"
    tp="$(yq "${yq_path}[${i}].to_port" "${yaml_file}")"

    # Build cidr_blocks list
    local cb_count cidr_hcl
    cb_count="$(yq "${yq_path}[${i}].cidr_blocks | length" "${yaml_file}")"
    cidr_hcl="["
    for j in $(seq 0 $((cb_count - 1))); do
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

# Helper: renders NACL rules
_render_nacl_rules() {
  local yaml_file="$1"
  local yq_path="$2"
  local count
  count="$(yq "${yq_path} | length" "${yaml_file}")"
  [[ "$count" == "0" || "$count" == "null" ]] && echo "[]" && return

  local hcl="["
  for i in $(seq 0 $((count - 1))); do
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
echo "── replace-vars.sh: done ────────────────────────────────────────────────"
