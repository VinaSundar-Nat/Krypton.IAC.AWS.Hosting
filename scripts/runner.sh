#!/usr/bin/env bash
# =============================================================================
# runner.sh
# On-prem / local Terraform runner using IAM Roles Anywhere.
#
# What it does:
#   1. Sources ARNs and config from scripts/vars.sh.
#   2. Writes an AWS CLI named profile whose credential_process calls
#      aws_signing_helper — so the Terraform AWS provider exchanges the local
#      X.509 certificate for temporary STS credentials automatically.
#   3. Sets TF_VAR_auth_mode=local and runs terraform init + the requested
#      command from the core/ directory.
#
# Prerequisites:
#   - aws_signing_helper on PATH:
#     https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
#   - .auth/create-cert.sh has been run (cert + key exist in .auth/cert/)
#   - .auth/setup.sh has been run and ARNs are set in scripts/vars.sh
#
# Usage:
#   ./scripts/runner.sh [ENV] [COMMAND] [PROGRAM] [FLAGS]
#   ./scripts/runner.sh dev plan                    — plan only, saves .tfplan file
#   ./scripts/runner.sh dev apply                   — plan → apply (two-phase)
#   ./scripts/runner.sh dev destroy                 — plan -destroy → apply
#   ./scripts/runner.sh dev apply kr-carevo
#   ./scripts/runner.sh prod apply kr-carevo -var="vpc_cidr=10.20.0.0/16"
#   ENV defaults to 'dev', COMMAND defaults to 'plan', PROGRAM defaults to 'kr-carevo'.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AUTH_DIR="${REPO_ROOT}/.auth"

# ── Load auth config (cert CN, TA role name, region, ARNs) ──────────────────
# shellcheck source=./vars.sh
source "${SCRIPT_DIR}/vars.sh"

SAFE_CN="$(echo "${CERT_CN}" | tr -- '- ' '_')"
SAFE_ROLE="$(echo "${TA_ROLE_NAME}" | tr -- '- ' '_')"
CERT_FILE="${AUTH_DIR}/cert/${SAFE_ROLE}.cert.pem"
KEY_FILE="${AUTH_DIR}/cert/${SAFE_ROLE}.key.pem"

# ── Validate prerequisites ────────────────────────────────────────────────────
if ! command -v aws_signing_helper &>/dev/null; then
  echo ""
  echo "ERROR: aws_signing_helper not found in PATH." >&2
  echo "       Download from:" >&2
  echo "       https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html" >&2
  exit 1
fi

for f in "$CERT_FILE" "$KEY_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required file not found: ${f}" >&2
    echo "       Run .auth/create-cert.sh first." >&2
    exit 1
  fi
done

# ── ARNs and profile name sourced from scripts/vars.sh ───────────────────────
AWS_REGION_VALUE="${AWS_REGION}"

for var_name in TA_ROLE_ARN TRUST_ANCHOR_ARN ROLESANYWHERE_PROFILE_ARN; do
  val="${!var_name}"
  if [[ -z "$val" || "$val" == *"ACCOUNT_ID"* ]]; then
    echo "ERROR: ${var_name} not populated in scripts/vars.sh." >&2
    echo "       Run .auth/setup.sh and copy the ARN into scripts/vars.sh." >&2
    exit 1
  fi
done

# ── Write credential_process profile to ~/.aws/config ────────────────────────
mkdir -p "${HOME}/.aws"
touch "${HOME}/.aws/config"
chmod 600 "${HOME}/.aws/config"

# Remove any existing block for this profile, then append the new one.
# Uses Python configparser — ships with macOS and all Linux distros.
python3 - <<PYEOF
import configparser, os

cfg_path = os.path.expanduser("~/.aws/config")
cfg = configparser.ConfigParser()
cfg.read(cfg_path)

section = "profile ${AWS_PROFILE_NAME}"
if cfg.has_section(section):
    cfg.remove_section(section)

cfg.add_section(section)
cfg.set(section, "region", "${AWS_REGION_VALUE}")
cfg.set(
    section,
    "credential_process",
    (
        "aws_signing_helper credential-process"
        " --certificate ${CERT_FILE}"
        " --private-key ${KEY_FILE}"
        " --trust-anchor-arn ${TRUST_ANCHOR_ARN}"
        " --profile-arn ${ROLESANYWHERE_PROFILE_ARN}"
        " --role-arn ${TA_ROLE_ARN}"
    ),
)

with open(cfg_path, "w") as fh:
    cfg.write(fh)
PYEOF

echo "AWS profile '${AWS_PROFILE_NAME}' written to ~/.aws/config"

# ── Run Terraform ─────────────────────────────────────────────────────────────
ENV="${1:-dev}"
TF_COMMAND="${2:-plan}"
PROGRAM="${3:-kr-carevo}"
shift 3 || true

# ── Ensure all scripts are executable ───────────────────────────────────────
chmod u+x "${SCRIPT_DIR}"/*.sh
chmod u+x "${SCRIPT_DIR}/configuration"/*.sh

# ── Install required tools (yq, etc.) ────────────────────────────────────────
"${SCRIPT_DIR}/install-deps.sh"

# ── Generate var files from environment YAML ────────────────────────────────────
"${SCRIPT_DIR}/configuration/replace-vars.sh" "${PROGRAM}" "${ENV}"

# ── Plan file name (timestamp-stamped, cleaned up on exit) ──────────────────
LOCALDT="$(date +%Y%m%d_%H%M%S)"
KR_PLAN="${REPO_ROOT}/core/kr_ops_${ENV}_${LOCALDT}.tfplan"

# ── Revert templates and clean plan file on exit (success or failure) ────────
# shellcheck disable=SC2064
trap "\"${SCRIPT_DIR}/revert-master-vars.sh\"; rm -f \"${KR_PLAN}\"" EXIT

export TF_VAR_auth_mode="local"

# ── Ensure symlinks for variable .tf declarations exist in core/ ─────────────
for tf_file in network security; do
  link="${REPO_ROOT}/core/${tf_file}.tf"
  target="variables/${tf_file}.tf"
  if [[ ! -L "${link}" ]]; then
    ln -sf "${target}" "${link}"
    echo "Symlinked: core/${tf_file}.tf → ${target}"
  fi
done

cd "${REPO_ROOT}/core"

VAR_FILES=( -var-file=variables/network.auto.tfvars -var-file=variables/security.auto.tfvars )

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform init (local — backend disabled)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform init -backend=false

# ── Plan ─────────────────────────────────────────────────────────────────────
PLAN_FLAGS=( "${VAR_FILES[@]}" -out="${KR_PLAN}" -lock=false -detailed-exitcode )
if [[ "${TF_COMMAND}" == "destroy" ]]; then
  PLAN_FLAGS+=( -destroy )
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform plan ${PLAN_FLAGS[*]} $*"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
set +e
echo "Running terraform plan with flags: ${PLAN_FLAGS[*]} $*"
terraform plan "${PLAN_FLAGS[@]}" "$@"
PLAN_EXIT=$?
set -e

if [[ ${PLAN_EXIT} -eq 1 ]]; then
  echo "ERROR: terraform plan failed." >&2
  exit 1
fi

if [[ ${PLAN_EXIT} -eq 0 ]]; then
  echo ""
  echo "No changes detected — infrastructure is up to date."
  exit 0
fi

# PLAN_EXIT=2: changes are pending
if [[ "${TF_COMMAND}" == "plan" ]]; then
  echo ""
  echo "Plan saved: $(basename "${KR_PLAN}")"
  echo "To apply:   ./scripts/runner.sh ${ENV} apply"
  exit 0
fi

# ── Apply from saved plan file ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform apply $(basename "${KR_PLAN}")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform apply -input=false -auto-approve "${KR_PLAN}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform show"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform show
