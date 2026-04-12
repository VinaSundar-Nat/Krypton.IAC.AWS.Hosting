#!/usr/bin/env bash
# =============================================================================
# revert-master-vars.sh
#
# Restores generated tfvars files to their master template state by copying
# each *.tfvars.tpl file back over the generated file.
#
# Files restored:
#   core/terraform.tfvars          ← core/terraform.tfvars.tpl
#   core/variables/*.auto.tfvars   ← core/variables/*.auto.tfvars.tpl
#
# Called automatically by runner.sh via EXIT trap after terraform completes
# (whether it succeeds or fails) so REPLACE_* tokens are always restored
# before any git operation.
#
# Can also be run manually:
#   ./scripts/revert-master-vars.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
VARS_DIR="${REPO_ROOT}/core/variables"

reverted=0

# ── core/terraform.tfvars ────────────────────────────────────────────────────
TFVARS_TPL="${REPO_ROOT}/core/terraform.tfvars.tpl"
TFVARS="${REPO_ROOT}/core/terraform.tfvars"
if [[ -f "${TFVARS_TPL}" ]]; then
  cp "${TFVARS_TPL}" "${TFVARS}"
  echo "  reverted: core/terraform.tfvars"
  (( reverted++ )) || true
else
  echo "WARNING: ${TFVARS_TPL} not found, skipping terraform.tfvars revert." >&2
fi

# ── core/variables/*.auto.tfvars ─────────────────────────────────────────────
if [[ ! -d "${VARS_DIR}" ]]; then
  echo "ERROR: ${VARS_DIR} not found." >&2
  exit 1
fi

for tpl in "${VARS_DIR}"/*.auto.tfvars.tpl; do
  [[ -f "${tpl}" ]] || continue
  dest="${tpl%.tpl}"
  cp "${tpl}" "${dest}"
  echo "  reverted: core/variables/$(basename "${dest}")"
  (( reverted++ )) || true
done

if [[ ${reverted} -eq 0 ]]; then
  echo "WARNING: no template files found to revert." >&2
else
  echo "revert-master-vars.sh: ${reverted} file(s) restored to template state"
fi
