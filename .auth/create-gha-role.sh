#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-gha-role.sh
# Creates the IAM role and OIDC provider for GitHub Actions authentication
# via sts:AssumeRoleWithWebIdentity.
#
# Usage:
#   ./create-gha-role.sh [--region <region>] [--profile <profile>]
#
# Requirements: aws-cli >= 2
# -----------------------------------------------------------------------------
set -euo pipefail

# ── Load defaults ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vars.sh
source "${SCRIPT_DIR}/vars.sh"

AWS_REGION="${AWS_REGION:-ap-southeast-2}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [options]"
  echo "  --region   <region>   AWS region   (default: ${AWS_REGION})"
  echo "  --profile  <name>     AWS profile  (default: ${AWS_PROFILE})"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)  AWS_REGION="$2";  shift 2 ;;
    --profile) AWS_PROFILE="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ── Create IAM role ───────────────────────────────────────────────────────────
POLICY_FILE="${SCRIPT_DIR}/roles/role-gha-sts.json"
ROLE_NAME="${GHA_ROLE_NAME}"

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: Role policy document not found: ${POLICY_FILE}" >&2
  exit 1
fi

echo ""
echo "Checking for existing IAM role '${ROLE_NAME}'..."
EXISTING_ROLE_ARN="$(aws iam get-role \
  --role-name "$ROLE_NAME" \
  --profile   "$AWS_PROFILE" \
  --output    json 2>/dev/null \
  | grep '"Arn"' \
  | sed 's/.*: *"\([^"]*\)".*/\1/' \
  | head -1 || true)"

if [[ -n "$EXISTING_ROLE_ARN" ]]; then
  echo ""
  echo "WARNING: IAM role '${ROLE_NAME}' already exists."
  echo "  ARN: ${EXISTING_ROLE_ARN}"
  echo ""
  read -r -p "Use existing role (skip creation)? [Y/n]: " SKIP_ROLE
  if [[ "${SKIP_ROLE:-Y}" =~ ^[Yy]$ ]]; then
    ROLE_ARN="$EXISTING_ROLE_ARN"
    echo "Using existing role."
  else
    echo "Aborting — delete or rename the existing role and re-run." >&2
    exit 1
  fi
else
  echo "Creating IAM role '${ROLE_NAME}'..."
  ROLE_RESPONSE="$(aws iam create-role \
    --role-name                   "$ROLE_NAME" \
    --assume-role-policy-document "file://${POLICY_FILE}" \
    --profile                     "$AWS_PROFILE" \
    --output                      json)"

  ROLE_ARN="$(echo "$ROLE_RESPONSE" \
    | grep '"Arn"' \
    | sed 's/.*: *"\([^"]*\)".*/\1/' \
    | head -1)"

  if [[ -n "$ROLE_ARN" ]]; then
    echo "IAM role '${ROLE_NAME}' created."

    # ── Create OIDC provider (idempotent) ──────────────────────────────────────
    if aws iam list-open-id-connect-providers \
        --profile "$AWS_PROFILE" \
        --output json 2>/dev/null \
      | grep -q "token.actions.githubusercontent.com"; then
      echo "OIDC provider already exists, skipping creation."
    else
      aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
        --profile "$AWS_PROFILE"
      echo "STS OIDC provider registered for GitHub Actions."
    fi
  else
    echo "ERROR: Failed to extract Role ARN from response." >&2
    exit 1
  fi
fi

# ── Attach inline permissions policy ─────────────────────────────────────────
PERMS_FILE="${SCRIPT_DIR}/roles/admin-role.json"
if [[ ! -f "$PERMS_FILE" ]]; then
  echo "ERROR: Permissions policy not found: ${PERMS_FILE}" >&2
  exit 1
fi
echo "Attaching inline policy to '${ROLE_NAME}'..."
aws iam put-role-policy \
  --role-name       "$ROLE_NAME" \
  --policy-name     "${ROLE_NAME}-admin-policy" \
  --policy-document "file://${PERMS_FILE}" \
  --profile         "$AWS_PROFILE"
echo "Inline policy attached."

# ── Derive account ID from caller identity ───────────────────────────────────────────
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --output text --query Account)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " GitHub Actions Role created successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Role Name    : ${ROLE_NAME}"
echo "  Role ARN     : ${ROLE_ARN}"
echo "  OIDC Provider: arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
echo "  Region       : ${AWS_REGION}"
echo "  Account      : ${ACCOUNT_ID}"
echo ""
echo "Add to your GitHub Actions workflow:"
echo ""
echo "  role-to-assume: \"${ROLE_ARN}\""
echo "  aws-region:     \"${AWS_REGION}\""
echo ""
