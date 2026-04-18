#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vars.sh
# Default configuration for runner.sh - locally executed Terraform with IAM Roles Anywhere.
# -----------------------------------------------------------------------------

CERT_CN="krypton-hosting-provider-trust-anchor"
TA_NAME="krypton-hosting-platform-digiplac"  # Name for trust anchor
TA_ROLE_NAME="krypton-hosting-tfl-runner"  # Name for role certificate
GHA_ROLE_NAME="krypton-hosting-gha-exec"  # Name for GitHub Actions role 
AWS_REGION="us-east-1"  # AWS region for signing role certificate

# ── IAM Roles Anywhere ARNs (local/on-prem only) ─────────────────────────────
# Fill in AWS_ACCOUNT_ID after running .auth/setup.sh
# AWS_ACCOUNT_ID="ACCOUNT_ID"
# TA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TA_ROLE_NAME}"
# TRUST_ANCHOR_ARN="arn:aws:rolesanywhere:${AWS_REGION}:${AWS_ACCOUNT_ID}:trust-anchor/ANCHOR_ID"
# ROLESANYWHERE_PROFILE_ARN="arn:aws:rolesanywhere:${AWS_REGION}:${AWS_ACCOUNT_ID}:profile/PROFILE_ID"
# AWS_PROFILE_NAME="krypton-ta"

AWS_ACCOUNT_ID="210620017481"
TA_ROLE_ARN="arn:aws:iam::210620017481:role/krypton-hosting-tfl-runner"
TRUST_ANCHOR_ARN="arn:aws:rolesanywhere:us-east-1:210620017481:trust-anchor/7ee811c7-2e68-4a83-899f-8019991397b2"
ROLESANYWHERE_PROFILE_ARN="arn:aws:rolesanywhere:us-east-1:210620017481:profile/b39948ee-310b-4395-9297-2278c18037f4"
AWS_PROFILE_NAME="krypton-ta"

