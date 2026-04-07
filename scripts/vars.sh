#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vars.sh
# Default configuration for create-cert.sh
# Override any variable by setting it in the environment before sourcing,
# or by passing the corresponding flag to create-cert.sh.
# -----------------------------------------------------------------------------

CERT_CN="krypton-hosting-provider-trust-anchor"
TA_NAME="krypton-hosting-platform-digiplac"  # Name for trust anchor
TA_ROLE_NAME="krypton-hosting-tfl-runner"  # Name for role certificate
GHA_ROLE_NAME="krypton-hosting-gha-exec"  # Name for GitHub Actions role 
AWS_REGION="us-east-1"  # AWS region for signing role certificate

# ── IAM Roles Anywhere ARNs (local/on-prem only) ─────────────────────────────
# Fill in AWS_ACCOUNT_ID after running .auth/setup.sh
AWS_ACCOUNT_ID="ACCOUNT_ID"
TA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TA_ROLE_NAME}"
TRUST_ANCHOR_ARN="arn:aws:rolesanywhere:${AWS_REGION}:${AWS_ACCOUNT_ID}:trust-anchor/ANCHOR_ID"
ROLESANYWHERE_PROFILE_ARN="arn:aws:rolesanywhere:${AWS_REGION}:${AWS_ACCOUNT_ID}:profile/PROFILE_ID"
AWS_PROFILE_NAME="krypton-ta"
