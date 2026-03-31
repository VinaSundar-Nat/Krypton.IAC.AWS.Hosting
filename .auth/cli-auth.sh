#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cli-auth.sh
# Interactively logs in to the AWS CLI and verifies the credentials.
# Exports ACCOUNT_ID and CALLER_ARN for use by calling scripts.
#
# Usage:
#   source ./cli-auth.sh   (must be sourced, not executed)
#
# Requirements: aws-cli >= 2
# -----------------------------------------------------------------------------

# ── Prerequisite checks ───────────────────────────────────────────────────────
for cmd in aws openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH." >&2
    exit 1
  fi
done

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
