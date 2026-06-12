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
for tf_file in network rules identity k8hosting; do
  link="${REPO_ROOT}/core/${tf_file}.tf"
  target="variables/${tf_file}.tf"
  if [[ ! -L "${link}" ]]; then
    ln -sf "${target}" "${link}"
    echo "Symlinked: core/${tf_file}.tf → ${target}"
  fi
done

cd "${REPO_ROOT}/core"

VAR_FILES=( -var-file=variables/network.auto.tfvars 
  -var-file=variables/rules.auto.tfvars   
  -var-file=variables/identity.auto.tfvars
  -var-file=variables/k8hosting.auto.tfvars
  )

# During full destroy, force Kubernetes/Helm-managed inputs to empty values.
# This prevents provider initialization failures when the cluster is absent or
# when cluster-dependent resources were already cleaned from state.
DESTROY_K8S_DISABLE_FLAGS=(
  -var 'namespace_map={}'
  -var 'lbc=[]'
  -var 'gateway_manifests={gc_name="",gateway=[]}'
  -var 'pod_identity={required=false,cluster_name="",roles=[]}'
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform init (local — local backend)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform init

# ── Detect two-phase apply requirement ───────────────────────────────────────
# kubernetes_manifest (GatewayClass/Gateway) requires a live cluster API at
# plan time to fetch CRD schemas. HashiCorp Terraform has no -exclude flag,
# so Phase 1 passes -var 'gateway_manifests={gc_name="",gateway=[]}' to force
# count=0 on all kubernetes_manifest resources (no API call needed). Phase 2
# then applies the manifests via -target once the cluster is live.
# If the cluster already exists the full plan runs normally (no two-phase needed).
PHASE_MANIFESTS_SEPARATELY=false
if grep -q 'eks_enabled *= *true' variables/k8hosting.auto.tfvars 2>/dev/null \
   && [[ "${TF_COMMAND}" != "destroy" ]]; then
  K8S_CLUSTER_NAME="$(grep 'kubernetes_cluster_name' variables/k8hosting.auto.tfvars \
    | sed 's/.*= *"\(.*\)"/\1/')"
  if [[ -n "${K8S_CLUSTER_NAME}" ]]; then
    echo "Checking if EKS cluster '${K8S_CLUSTER_NAME}' exists in AWS..."
    if ! AWS_PROFILE="${AWS_PROFILE_NAME}" aws eks describe-cluster \
         --name "${K8S_CLUSTER_NAME}" \
         --region "${AWS_REGION}" \
         --output text &>/dev/null 2>&1; then
      PHASE_MANIFESTS_SEPARATELY=true
      echo "✓ EKS cluster '${K8S_CLUSTER_NAME}' does not yet exist — two-phase apply enabled."
    else
      echo "✓ EKS cluster '${K8S_CLUSTER_NAME}' already exists — full single-phase apply."
    fi
  fi
fi

# ── Pre-destroy: remove Kubernetes namespaces before cluster teardown ─────────
# The Kubernetes provider resolves its endpoint from data.aws_eks_cluster.kr_target.
# During a full destroy that data source resolves to null (its depends_on dependency
# is scheduled for deletion), causing the provider to fall back to http://localhost.
#
# Two cases handled:
#   1. Cluster still live  → targeted terraform destroy (API call, clean removal)
#   2. Cluster already gone → terraform state rm (drops orphaned state, no API needed)
if [[ "${TF_COMMAND}" == "destroy" ]]; then
  K8S_STATE_MODULES=(
    module.deploy-kr-eks-namespaces
    module.deploy-kr-eks-alb
    module.deploy-kr-eks-manifests
  )

  HAS_K8S_STATE=false
  for mod in "${K8S_STATE_MODULES[@]}"; do
    if terraform state list "${mod}" >/dev/null 2>&1; then
      HAS_K8S_STATE=true
      break
    fi
  done

  if [[ "${HAS_K8S_STATE}" == "true" ]]; then
    # Read the cluster name written by replace-vars.sh into k8hosting.auto.tfvars
    K8S_CLUSTER_NAME="$(grep 'kubernetes_cluster_name' variables/k8hosting.auto.tfvars \
      | sed 's/.*= *"\(.*\)"/\1/')"
    EKS_ENABLED_IN_VARS=false
    if grep -q 'eks_enabled *= *true' variables/k8hosting.auto.tfvars 2>/dev/null; then
      EKS_ENABLED_IN_VARS=true
    fi

    # If EKS is disabled (or cluster name is empty), provider config will fall back
    # to localhost during destroy. In that case, remove namespace state directly.
    if [[ "${EKS_ENABLED_IN_VARS}" != "true" || -z "${K8S_CLUSTER_NAME}" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo " Pre-destroy: EKS disabled or cluster name missing in tfvars."
      echo " Removing Kubernetes/Helm module state to avoid localhost provider fallback."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      for mod in "${K8S_STATE_MODULES[@]}"; do
        if terraform state list "${mod}" >/dev/null 2>&1; then
          terraform state rm "${mod}"
        fi
      done
      K8S_CLUSTER_NAME=""
    fi

    # Check whether the cluster API is still reachable in AWS
    CLUSTER_EXISTS=false
    if [[ -n "${K8S_CLUSTER_NAME}" ]] && \
       AWS_PROFILE="${AWS_PROFILE_NAME}" aws eks describe-cluster \
         --name "${K8S_CLUSTER_NAME}" \
         --region "${AWS_REGION}" \
         --output text &>/dev/null; then
      CLUSTER_EXISTS=true
    fi

    if [[ "${CLUSTER_EXISTS}" == "true" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo " Pre-destroy: Kubernetes/Helm modules (targeted — cluster live)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      set +e
      terraform destroy \
        "${VAR_FILES[@]}" \
        "${DESTROY_K8S_DISABLE_FLAGS[@]}" \
        -target=module.deploy-kr-eks-alb \
        -target=module.deploy-kr-eks-manifests \
        -target=module.deploy-kr-eks-namespaces \
        -lock=false \
        -auto-approve
      NS_DESTROY_EXIT=$?
      set -e
      if [[ ${NS_DESTROY_EXIT} -ne 0 ]]; then
        echo "WARNING: Targeted Kubernetes/Helm destroy failed (exit ${NS_DESTROY_EXIT})." >&2
        echo "         Falling back to state cleanup for Kubernetes/Helm modules." >&2
        for mod in "${K8S_STATE_MODULES[@]}"; do
          if terraform state list "${mod}" >/dev/null 2>&1; then
            terraform state rm "${mod}"
          fi
        done
      fi
    else
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo " Pre-destroy: EKS cluster '${K8S_CLUSTER_NAME}' not found in AWS."
      echo " Removing orphaned Kubernetes/Helm state entries (no API call needed)."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      for mod in "${K8S_STATE_MODULES[@]}"; do
        if terraform state list "${mod}" >/dev/null 2>&1; then
          terraform state rm "${mod}"
        fi
      done
    fi
  else
    echo ""
    echo "Pre-destroy: no Kubernetes/Helm resources in state — skipping."
  fi
fi

# ── Plan ─────────────────────────────────────────────────────────────────────
PLAN_FLAGS=( "${VAR_FILES[@]}" -out="${KR_PLAN}" -lock=false -detailed-exitcode -refresh=false )
if [[ "${TF_COMMAND}" == "destroy" ]]; then
  PLAN_FLAGS+=( -destroy )
  PLAN_FLAGS+=( "${DESTROY_K8S_DISABLE_FLAGS[@]}" )
fi
# When the cluster doesn't exist yet, override gateway_manifests to an empty
# value so all kubernetes_manifest resources have count=0. This avoids the
# "no client config" error because the Kubernetes provider is never asked to
# connect during Phase 1 planning. HashiCorp Terraform has no -exclude flag.
if [[ "${PHASE_MANIFESTS_SEPARATELY}" == "true" ]]; then
  PLAN_FLAGS+=( -var 'gateway_manifests={gc_name="",gateway=[]}')
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
  if [[ "${PHASE_MANIFESTS_SEPARATELY}" == "true" ]]; then
    echo "Note: EKS manifests (GatewayClass/Gateway) omitted from this plan"
    echo "      (cluster not yet live). Phase 2 will apply them automatically"
    echo "      after 'apply' creates the cluster."
  fi
  echo "To apply:   ./scripts/runner.sh ${ENV} apply"
  exit 0
fi

# ── Apply from saved plan file ────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform apply $(basename "${KR_PLAN}")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform apply -input=false -auto-approve -refresh=false "${KR_PLAN}"

# ── Phase 2: EKS Manifests ────────────────────────────────────────────────────
# Apply GatewayClass and Gateway resources now that the cluster is live.
# Only runs when the cluster was newly created in this apply (Phase 1 suppressed
# kubernetes_manifest via the gateway_manifests override; now we apply with full
# values using -target so the Kubernetes provider can connect to the live cluster).
if [[ "${PHASE_MANIFESTS_SEPARATELY}" == "true" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " Phase 2: EKS Manifests (GatewayClass / Gateway)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # ── Wait for cluster API to be ready ──────────────────────────────────────
  # Kubernetes provider needs the cluster API endpoint to be responding.
  # Retry aws eks get-token to validate cluster access before Phase 2 plan.
  K8S_CLUSTER_NAME="$(grep 'kubernetes_cluster_name' variables/k8hosting.auto.tfvars \
    | sed 's/.*= *"\(.*\)"/\1/')"
  
  if [[ -n "${K8S_CLUSTER_NAME}" ]]; then
    MAX_RETRIES=30
    RETRY_DELAY=10
    RETRY_COUNT=0
    
    echo "Waiting for EKS cluster API to be ready (max ${MAX_RETRIES} attempts, ${RETRY_DELAY}s between)..."
    while [[ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]]; do
      if AWS_PROFILE="${AWS_PROFILE_NAME}" aws eks get-token \
           --cluster-name "${K8S_CLUSTER_NAME}" \
           --region "${AWS_REGION}" &>/dev/null; then
        echo "✓ Cluster API is ready."
        break
      fi
      RETRY_COUNT=$((RETRY_COUNT + 1))
      if [[ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]]; then
        echo "  Attempt ${RETRY_COUNT}/${MAX_RETRIES}: Cluster API not yet ready, retrying in ${RETRY_DELAY}s..."
        sleep "${RETRY_DELAY}"
      fi
    done
    
    if [[ ${RETRY_COUNT} -eq ${MAX_RETRIES} ]]; then
      echo "⚠ WARNING: Cluster API did not become ready after ${MAX_RETRIES} attempts." >&2
      echo "           Proceeding with Phase 2 — if errors occur, cluster may still be initializing." >&2
    fi
  fi

  KR_PLAN_P2="${REPO_ROOT}/core/kr_ops_${ENV}_${LOCALDT}_manifests.tfplan"
  set +e
  terraform plan \
    "${VAR_FILES[@]}" \
    -target=data.aws_eks_cluster.kr_target \
    -target=module.deploy-kr-eks-manifests \
    -out="${KR_PLAN_P2}" \
    -lock=false \
    -detailed-exitcode
  P2_PLAN_EXIT=$?
  set -e
  if [[ ${P2_PLAN_EXIT} -eq 1 ]]; then
    echo "ERROR: Phase 2 plan (EKS manifests) failed." >&2
    rm -f "${KR_PLAN_P2}"
    exit 1
  fi
  if [[ ${P2_PLAN_EXIT} -eq 2 ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " terraform apply (Phase 2 — manifests)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    terraform apply -input=false -auto-approve -refresh=false "${KR_PLAN_P2}"
  else
    echo "Phase 2: no manifest changes — already up to date."
  fi
  rm -f "${KR_PLAN_P2}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " terraform show"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
terraform show
