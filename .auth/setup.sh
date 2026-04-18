#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup.sh
# Orchestrates the full AWS IAM setup for Krypton Hosting platform.
#
# Order:
#   1. create-ta-role.sh  — Trust anchor, TA IAM role, Roles Anywhere profile
#   2. create-gha-role.sh — GitHub Actions IAM role + OIDC provider
#
# Login is performed once here and credentials are written to the
# named AWS CLI profile, shared by all sub-scripts.
#
# Usage:
#   ./setup.sh [--region <region>] [--profile <profile>]
#
# Requirements: aws-cli >= 2, openssl
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vars.sh
source "${SCRIPT_DIR}/vars.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
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

export AWS_REGION
export AWS_PROFILE

# ── AWS CLI Login (once for all steps) ───────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " AWS CLI Login"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# shellcheck source=cli-auth.sh
source "${SCRIPT_DIR}/cli-auth.sh"

# ── Step 1: Trust Anchor + TA Role + Roles Anywhere Profile ──────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Step 1 of 2 — Trust Anchor Role Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
chmod u+x "${SCRIPT_DIR}/create-ta-role.sh"
"${SCRIPT_DIR}/create-ta-role.sh" --region "$AWS_REGION" --profile "$AWS_PROFILE"

# ── Step 2: GitHub Actions Role + OIDC Provider ──────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Step 2 of 2 — GitHub Actions Role Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
chmod u+x "${SCRIPT_DIR}/create-gha-role.sh"
"${SCRIPT_DIR}/create-gha-role.sh" --region "$AWS_REGION" --profile "$AWS_PROFILE"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Setup complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  TA Role     : ${TA_ROLE_NAME}"
echo "  GHA Role    : ${GHA_ROLE_NAME}"
echo "  Profile     : ${AWS_PROFILE}"
echo "  Region      : ${AWS_REGION}"
echo ""

chmod 600 "${SCRIPT_DIR}/vars.sh"
