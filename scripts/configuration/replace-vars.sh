#!/usr/bin/env bash
# =============================================================================
# replace-vars.sh  (main orchestrator)
# Resolves environment and component settings from a SID (service identifier),
# then generates Terraform variable value files by delegating to logical
# sub-scripts.
#
# Sources:
#   environment/org.yml                      → organisation, program, active env
#   environment/<ENV>/platform/network.yml   → vpc, AZs, NAT  (component by SID)
#   environment/<ENV>/zoning/*.yml            → subnet_zones map
#   environment/<ENV>/platform/rules.yml     → SG and NACL rules
#
# Outputs:
#   core/terraform.tfvars                    → organisation, program, environment tags
#   core/variables/network.auto.tfvars       → via network-vars.sh
#   core/variables/security.auto.tfvars      → via rules-vars.sh
#
# Usage:
#   ./scripts/configuration/replace-vars.sh kr-carevo dev
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SID="${1:?Usage: replace-vars.sh <sid> <env>  e.g. replace-vars.sh kr-carevo dev}"
ENV="${2:?Usage: replace-vars.sh <sid> <env>  e.g. replace-vars.sh kr-carevo dev}"
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
REGION="$(yq '.organisation.program[] | select(.sid == "'"${SID}"'") | .region' "${ORG_YAML}")"
ENV_NAME="${ENV}"

if [[ -z "${PROGRAM_NAME}" || "${PROGRAM_NAME}" == "null" ]]; then
  echo "ERROR: sid '${SID}' not found in ${ORG_YAML}" >&2
  exit 1
fi
if [[ -z "${REGION}" || "${REGION}" == "null" ]]; then
  echo "ERROR: region not set for sid '${SID}' in ${ORG_YAML}" >&2
  exit 1
fi
if [[ -z "${ENV_NAME}" || "${ENV_NAME}" == "null" ]]; then
  echo "ERROR: tags.environment not set for sid '${SID}' in ${ORG_YAML}" >&2
  exit 1
fi

ENV_DIR="${REPO_ROOT}/environment/${ENV_NAME}"
NET_YAML="${ENV_DIR}/platform/network.yml"
RULES_YAML="${ENV_DIR}/platform/rules.yml"
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
_sub "${TFVARS}" "REPLACE_REGION"       "${REGION}"
echo "Written: ${TFVARS}"

# =============================================================================
# network.auto.tfvars  — delegated to network-vars.sh
# =============================================================================
# shellcheck source=./network-vars.sh
source "${SCRIPT_DIR}/network-vars.sh"

# =============================================================================
# security.auto.tfvars — delegated to rules-vars.sh
# =============================================================================
# shellcheck source=./rules-vars.sh
source "${SCRIPT_DIR}/rules-vars.sh"

echo "── replace-vars.sh: done ────────────────────────────────────────────────"
