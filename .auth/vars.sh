#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vars.sh
# Default configuration for create-cert.sh
# Override any variable by setting it in the environment before sourcing,
# or by passing the corresponding flag to create-cert.sh.
# -----------------------------------------------------------------------------

OUT_DIR="./cert"
CERT_CN="krypton-hosting-provider-trust-anchor"
CERT_ORG="Krypton"
CERT_OU="Platform Engineering"
CERT_COUNTRY="AU"
CERT_STATE="NSW"
CERT_LOCALITY="Sydney"
CERT_DAYS="3650"       # 10 years;
KEY_TYPE="ec"          # ec | rsa
RSA_BITS="4096"        # only used when KEY_TYPE=rsa
EC_CURVE="prime256v1"  # prime256v1 (P-256) | secp384r1 (P-384)
TA_NAME="krypton-hosting-platform-digiplac"  # Name for trust anchor
TA_ROLE_NAME="krypton-hosting-tfl-runner"  # Name for role certificate
GHA_ROLE_NAME="krypton-hosting-gha-exec"  # Name for GitHub Actions role 
AWS_REGION="us-east-1"  # AWS region for signing role certificate
# Revoke after use
AWS_KEY_ID="DO NOT COMMIT"   # AWS Secret Access Key for signing role certificate # AWS KMS Key ID for signing role certificate 
