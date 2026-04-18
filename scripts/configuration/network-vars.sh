#!/usr/bin/env bash
# =============================================================================
# network-vars.sh
# Generates core/variables/network.auto.tfvars from environment YAML sources.
#
# Sourced by replace-vars.sh — expects the following to already be set:
#   SID           – service identifier (e.g. kr-carevo)
#   NET_YAML      – path to environment/<ENV>/platform/network.yml
#   ZONING_DIR    – path to environment/<ENV>/zoning/
#   OUT_DIR       – path to core/variables/
#   ORG_NAME      – organisation name
#   PROGRAM_NAME  – program name
#   ENV_NAME      – environment name (dev|stage|prod)
#   _sub()        – token substitution helper from replace-vars.sh
# =============================================================================

echo "── network-vars.sh: generating network.auto.tfvars ─────────────────────"

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
DHCP_ENABLED="$(yq "${SEL} | .dhcp_options.enabled"             "${NET_YAML}")"
DHCP_DOMAIN="$(yq  "${SEL} | .dhcp_options.domain_name"         "${NET_YAML}")"
DHCP_PROVIDER="$(yq "${SEL} | .dhcp_options.provider"           "${NET_YAML}")"

# Build domain_name_servers as HCL list: ["1.1.1.1", "1.0.0.1"]
DNS_COUNT="$(yq "${SEL} | .dhcp_options.domain_name_servers | length" "${NET_YAML}")"
DHCP_DNS_HCL="["
for i in $(seq 0 1 $((DNS_COUNT - 1))); do
  DNS="$(yq "${SEL} | .dhcp_options.domain_name_servers[${i}]" "${NET_YAML}")"
  [[ $i -gt 0 ]] && DHCP_DNS_HCL+=", "
  DHCP_DNS_HCL+="\"${DNS}\""
done
DHCP_DNS_HCL+="]"

DHCP_HCL="{ enabled = ${DHCP_ENABLED}, domain_name = \"${DHCP_DOMAIN}\", domain_name_servers = ${DHCP_DNS_HCL}, provider = \"${DHCP_PROVIDER}\" }"

# Build vpc_tags map from network.yaml component.vpc.tags
VPC_TAGS_HCL="{"
while IFS= read -r key; do
  [[ -z "$key" || "$key" == "null" ]] && continue
  val="$(yq "${SEL} | .vpc.tags.${key}" "${NET_YAML}")"
  VPC_TAGS_HCL+=$'\n'"  ${key} = \"${val}\""
done <<< "$(yq "${SEL} | .vpc.tags | keys | .[]" "${NET_YAML}")"
VPC_TAGS_HCL+=$'\n'"}"

# Build AZ list in HCL format: ["us-east-1a", "us-east-1b", ...]
AZ_COUNT="$(yq "${SEL} | .availability_zone | length" "${NET_YAML}")"
AZS_HCL="["
for i in $(seq 0 1 $((AZ_COUNT - 1))); do
  AZ="$(yq "${SEL} | .availability_zone[${i}]" "${NET_YAML}")"
  [[ $i -gt 0 ]] && AZS_HCL+=", "
  AZS_HCL+="\"${AZ}\""
done
AZS_HCL+="]"

# Build subnets list from network.yaml component.subnets[]
SUBNET_COUNT="$(yq "${SEL} | .subnets | length" "${NET_YAML}")"
SUBNETS_HCL="["
for i in $(seq 0 1 $((SUBNET_COUNT - 1))); do
  SN_NAME="$(yq "${SEL} | .subnets[${i}].name"              "${NET_YAML}")"
  SN_CIDR="$(yq "${SEL} | .subnets[${i}].cidr"              "${NET_YAML}")"
  SN_TYPE="$(yq "${SEL} | .subnets[${i}].type"              "${NET_YAML}")"
  SN_AZ_COUNT="$(yq "${SEL} | .subnets[${i}].availability_zone | length" "${NET_YAML}")"
  SN_AZ_HCL="["
  for j in $(seq 0 1 $((SN_AZ_COUNT - 1))); do
    SN_AZ="$(yq "${SEL} | .subnets[${i}].availability_zone[${j}]" "${NET_YAML}")"
    [[ $j -gt 0 ]] && SN_AZ_HCL+=", "
    SN_AZ_HCL+="\"${SN_AZ}\""
  done
  SN_AZ_HCL+="]"
  [[ $i -gt 0 ]] && SUBNETS_HCL+=","
  SUBNETS_HCL+=$'\n'"  { name = \"${SN_NAME}\", cidr = \"${SN_CIDR}\", type = \"${SN_TYPE}\", availability_zone = ${SN_AZ_HCL} }"
done
SUBNETS_HCL+=$'\n'"]"

# Build route_tables list from network.yaml component.route_tables[]
RT_COUNT="$(yq "${SEL} | .route_tables | length" "${NET_YAML}")"
RT_HCL="["
for i in $(seq 0 1 $((RT_COUNT - 1))); do
  RT_NAME="$(yq "${SEL} | .route_tables[${i}].name" "${NET_YAML}")"
  RT_TYPE="$(yq "${SEL} | .route_tables[${i}].type" "${NET_YAML}")"
  ROUTE_COUNT="$(yq "${SEL} | .route_tables[${i}].routes | length" "${NET_YAML}")"
  ROUTES_HCL="["
  for j in $(seq 0 1 $((ROUTE_COUNT - 1))); do
    DEST="$(yq "${SEL} | .route_tables[${i}].routes[${j}].destination" "${NET_YAML}")"
    TARGET="$(yq "${SEL} | .route_tables[${i}].routes[${j}].target" "${NET_YAML}")"
    [[ $j -gt 0 ]] && ROUTES_HCL+=","
    ROUTES_HCL+=" { destination = \"${DEST}\", target = \"${TARGET}\" }"
  done
  ROUTES_HCL+=" ]"
  [[ $i -gt 0 ]] && RT_HCL+=","
  RT_HCL+=$'\n'"  { name = \"${RT_NAME}\", type = \"${RT_TYPE}\", routes = ${ROUTES_HCL} }"
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
