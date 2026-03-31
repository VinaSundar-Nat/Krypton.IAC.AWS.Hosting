#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-ta-role.sh
# Creates the IAM Roles Anywhere trust anchor, IAM role, and profile
# for local Terraform execution via X.509 certificate authentication.
#
# Usage:
#   ./create-ta-role.sh [--region <region>] [--profile <profile>]
#
# Requirements: aws-cli >= 2, openssl
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

# ── Derive expected certificate path ─────────────────────────────────────────
SAFE_CN="$(echo "$CERT_CN" | tr -- '- ' '_')"
CERT_FILE="${SCRIPT_DIR}/${OUT_DIR}/${SAFE_CN}.cert.pem"

if [[ "$OUT_DIR" = ./* || "$OUT_DIR" = "." ]]; then
  CERT_FILE="${SCRIPT_DIR}/$(echo "$OUT_DIR" | sed 's|^\./||')/${SAFE_CN}.cert.pem"
fi

echo "Looking for certificate: ${CERT_FILE}"
if [[ ! -f "$CERT_FILE" ]]; then
  echo "" >&2
  echo "ERROR: Certificate not found: ${CERT_FILE}" >&2
  echo "       Run ./create-cert.sh first to generate it." >&2
  exit 1
fi

if ! openssl x509 -in "$CERT_FILE" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
  echo "ERROR: ${CERT_FILE} does not appear to be a CA certificate (CA:TRUE missing)." >&2
  exit 1
fi
echo "Certificate found and verified as CA cert."

# ── Check if trust anchor already exists ─────────────────────────────────────
echo "Checking for existing trust anchor '${TA_NAME}'..."
ANCHORS="$(aws rolesanywhere list-trust-anchors \
  --profile "$AWS_PROFILE" \
  --region  "$AWS_REGION"  \
  --output  json 2>/dev/null || echo '{"trustAnchors":[]}')"

EXISTING_ARN="$(echo "$ANCHORS" \
  | grep -A 5 "\"name\": *\"${TA_NAME}\"" \
  | grep '"trustAnchorArn"' \
  | sed 's/.*: *"\([^"]*\)".*/\1/' \
  | head -1 || true)"

if [[ -n "$EXISTING_ARN" ]]; then
  echo ""
  echo "WARNING: A trust anchor named '${TA_NAME}' already exists."
  echo "  ARN: ${EXISTING_ARN}"
  echo ""
  read -r -p "Re-use existing anchor (skip creation)? [Y/n]: " SKIP_CREATE
  if [[ "${SKIP_CREATE:-Y}" =~ ^[Yy]$ ]]; then
    TRUST_ANCHOR_ARN="$EXISTING_ARN"
    echo "Using existing trust anchor."
  else
    echo "Aborting — delete or rename the existing anchor and re-run." >&2
    exit 1
  fi
else
  echo "Creating IAM Roles Anywhere trust anchor '${TA_NAME}'..."
  echo "Uploading certificate... (this may take a moment)"
  RESPONSE="$(aws rolesanywhere create-trust-anchor \
    --name    "$TA_NAME" \
    --source  "{\"sourceType\":\"CERTIFICATE_BUNDLE\",\"sourceData\":{\"x509CertificateData\":\"$(awk '{printf "%s\\n", $0}' "$CERT_FILE")\"}}" \
    --enabled \
    --profile "$AWS_PROFILE" \
    --region  "$AWS_REGION"  \
    --output  json)"

  TRUST_ANCHOR_ARN="$(echo "$RESPONSE" \
    | grep '"trustAnchorArn"' \
    | sed 's/.*: *"\([^"]*\)".*/\1/')"
  echo "Trust anchor created."
fi

# ── Create IAM role ───────────────────────────────────────────────────────────
POLICY_FILE="${SCRIPT_DIR}/roles/role-ta.json"
ROLE_NAME="${TA_ROLE_NAME}"
ROLESANYWHERE_PROFILE_NAME="${ROLE_NAME}-profile"

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

  if [[ -z "$ROLE_ARN" ]]; then
    echo "ERROR: Failed to extract Role ARN from response." >&2
    exit 1
  fi
  echo "IAM role '${ROLE_NAME}' created."
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

# ── Create IAM Roles Anywhere profile ────────────────────────────────────────
echo ""
echo "Checking for existing Roles Anywhere profile '${ROLESANYWHERE_PROFILE_NAME}'..."
ALL_PROFILES="$(aws rolesanywhere list-profiles \
  --profile "$AWS_PROFILE" \
  --region  "$AWS_REGION"  \
  --output  json 2>/dev/null || echo '{"profiles":[]}')"

EXISTING_PROFILE_ARN="$(echo "$ALL_PROFILES" \
  | grep -A 5 "\"name\": *\"${ROLESANYWHERE_PROFILE_NAME}\"" \
  | grep '"profileArn"' \
  | sed 's/.*: *"\([^"]*\)".*/\1/' \
  | head -1 || true)"

if [[ -n "$EXISTING_PROFILE_ARN" ]]; then
  echo ""
  echo "WARNING: A Roles Anywhere profile named '${ROLESANYWHERE_PROFILE_NAME}' already exists."
  echo "  ARN: ${EXISTING_PROFILE_ARN}"
  echo ""
  read -r -p "Use existing profile (skip creation)? [Y/n]: " SKIP_PROFILE
  if [[ "${SKIP_PROFILE:-Y}" =~ ^[Yy]$ ]]; then
    PROFILE_ARN="$EXISTING_PROFILE_ARN"
    echo "Using existing profile."
  else
    echo "Aborting — delete or rename the existing profile and re-run." >&2
    exit 1
  fi
else
  echo "Creating Roles Anywhere profile '${ROLESANYWHERE_PROFILE_NAME}'..."
  PROFILE_RESPONSE="$(aws rolesanywhere create-profile \
    --name      "$ROLESANYWHERE_PROFILE_NAME" \
    --role-arns "[\"${ROLE_ARN}\"]" \
    --enabled   \
    --profile   "$AWS_PROFILE" \
    --region    "$AWS_REGION"  \
    --output    json)"

  PROFILE_ARN="$(echo "$PROFILE_RESPONSE" \
    | grep '"profileArn"' \
    | sed 's/.*: *"\([^"]*\)".*/\1/' \
    | head -1)"
  echo "Roles Anywhere profile created."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Trust Anchor, Role, and Profile created successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Trust Anchor Name : ${TA_NAME}"
echo "  Trust Anchor ARN  : ${TRUST_ANCHOR_ARN}"
echo "  Role Name         : ${ROLE_NAME}"
echo "  Role ARN          : ${ROLE_ARN}"
echo "  Profile Name      : ${ROLESANYWHERE_PROFILE_NAME}"
echo "  Profile ARN       : ${PROFILE_ARN}"
echo "  Region            : ${AWS_REGION}"
echo ""
echo "Add to your Terraform variables (e.g. terraform.tfvars):"
echo ""
echo "  trust_anchor_arn          = \"${TRUST_ANCHOR_ARN}\""
echo "  role_arn                  = \"${ROLE_ARN}\""
echo "  rolesanywhere_profile_arn = \"${PROFILE_ARN}\""
echo ""
