#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# upload-cert.sh
# Interactively logs in to the AWS CLI, verifies the trust-anchor certificate
# exists locally, then creates an IAM Roles Anywhere Trust Anchor.
#
# The resulting Trust Anchor ARN is printed and can be referenced in Terraform
# via the aws_rolesanywhere_trust_anchor data source or resource.
#
# Usage:
#   ./upload-cert.sh [--region <region>] [--profile <profile>]
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
  echo "  --region   <region>   AWS region              (default: ${AWS_REGION})"
  echo "  --profile  <name>     AWS CLI profile          (default: ${AWS_PROFILE})"
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

# ── Prerequisite checks ───────────────────────────────────────────────────────
for cmd in aws openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH." >&2
    exit 1
  fi
done

# ── Derive expected certificate path (same safe-name logic as create-cert.sh) ─
SAFE_CN="$(echo "$CERT_CN" | tr -- '- ' '_')"
CERT_FILE="${SCRIPT_DIR}/${OUT_DIR}/${SAFE_CN}.cert.pem"

# Strip leading ./ from OUT_DIR for the resolved path when OUT_DIR is relative
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

# Sanity-check the cert is a CA cert (basicConstraints CA:TRUE)
if ! openssl x509 -in "$CERT_FILE" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
  echo "ERROR: ${CERT_FILE} does not appear to be a CA certificate (CA:TRUE missing)." >&2
  exit 1
fi
echo "Certificate found and verified as CA cert."

# ── Interactive AWS login ─────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS CLI Login"
echo " Profile : ${AWS_PROFILE}"
echo " Region  : ${AWS_REGION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Enter your AWS credentials (input is hidden for secret key):"
echo ""

read -r -p "  AWS Access Key ID     : " INPUT_KEY_ID
if [[ -z "$INPUT_KEY_ID" ]]; then
  echo "Access Key ID cannot be empty. Using default ${AWS_KEY_ID}" >&2
  INPUT_KEY_ID="${AWS_KEY_ID}"
fi

read -r -s -p "  AWS Secret Access Key : " INPUT_SECRET_KEY
echo ""
if [[ -z "$INPUT_SECRET_KEY" ]]; then
  echo "ERROR: Secret Access Key cannot be empty." >&2
  exit 1
fi

read -r -p "  Session Token (leave blank if not using STS/SSO): " INPUT_SESSION_TOKEN
echo ""

# Write credentials into the named profile
aws configure set aws_access_key_id     "$INPUT_KEY_ID"     --profile "$AWS_PROFILE"
aws configure set aws_secret_access_key "$INPUT_SECRET_KEY" --profile "$AWS_PROFILE"
aws configure set region                "$AWS_REGION"       --profile "$AWS_PROFILE"
aws configure set output                "json"              --profile "$AWS_PROFILE"

if [[ -n "$INPUT_SESSION_TOKEN" ]]; then
  aws configure set aws_session_token "$INPUT_SESSION_TOKEN" --profile "$AWS_PROFILE"
fi

# Erase credential variables from memory immediately after storing
INPUT_KEY_ID=""
INPUT_SECRET_KEY=""
INPUT_SESSION_TOKEN=""

# ── Verify the credentials ────────────────────────────────────────────────────
echo "Verifying credentials..."
IDENTITY="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --output json 2>&1)" || {
  echo ""
  echo "ERROR: AWS credential verification failed." >&2
  echo "$IDENTITY" >&2
  exit 1
}

ACCOUNT_ID="$(echo "$IDENTITY" | grep '"Account"' | sed 's/.*: *"\([^"]*\)".*/\1/')"
CALLER_ARN="$(echo "$IDENTITY"  | grep '"Arn"'     | sed 's/.*: *"\([^"]*\)".*/\1/')"

echo ""
echo "  Logged in as : ${CALLER_ARN}"
echo "  Account      : ${ACCOUNT_ID}"
echo ""

# ── Check if trust anchor already exists ─────────────────────────────────────
echo "Checking for existing trust anchor '${TA_NAME}'..."
EXISTING_ARN=""
ANCHORS="$(aws rolesanywhere list-trust-anchors \
  --profile "$AWS_PROFILE" \
  --region  "$AWS_REGION"  \
  --output  json 2>/dev/null || echo '{"trustAnchors":[]}')"

# Extract ARN if a trust anchor with the same name exists
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
  # ── Create the trust anchor ─────────────────────────────────────────────────
  echo "Creating IAM Roles Anywhere trust anchor '${TA_NAME}'..."
  echo "Uploading certificate and creating trust anchor... (this may take a moment)"
  echo "${CERT_FILE}"
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
fi

# ── Create IAM role ───────────────────────────────────────────────────────────
POLICY_FILE="${SCRIPT_DIR}/role.json"
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
  echo "IAM role created."
fi

# ── Attach inline permissions policy ─────────────────────────────────────────
PERMS_FILE="${SCRIPT_DIR}/admin-role.json"
if [[ ! -f "$PERMS_FILE" ]]; then
  echo "ERROR: Permissions policy not found: ${PERMS_FILE}" >&2
  exit 1
fi
echo "Attaching inline policy from admin-role.json to '${ROLE_NAME}'..."
aws iam put-role-policy \
  --role-name     "$ROLE_NAME" \
  --policy-name   "${ROLE_NAME}-admin-policy" \
  --policy-document "file://${PERMS_FILE}" \
  --profile       "$AWS_PROFILE"
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

# ── Output ────────────────────────────────────────────────────────────────────
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
echo "  Account           : ${ACCOUNT_ID}"
echo ""
echo "Add to your Terraform variables (e.g. terraform.tfvars):"
echo ""
echo "  trust_anchor_arn          = \"${TRUST_ANCHOR_ARN}\""
echo "  role_arn                  = \"${ROLE_ARN}\""
echo "  rolesanywhere_profile_arn = \"${PROFILE_ARN}\""
echo ""
