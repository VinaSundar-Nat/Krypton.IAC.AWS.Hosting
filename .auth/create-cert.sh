#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-cert.sh
# Generates two certificates for AWS IAM Roles Anywhere:
#
#   1. CA certificate  (<cn>.cert.pem + <cn>.key.pem)
#      → Upload to IAM Roles Anywhere as the Trust Anchor source.
#        Keep the CA key secret — it is only needed to sign leaf certs.
#
#   2. Leaf certificate  (<role-name>.cert.pem + <role-name>.key.pem)
#      → Used by aws_signing_helper at runtime (referenced by runner.sh).
#        This is the cert that IAM Roles Anywhere validates against the CA.
#
# Requirements: openssl >= 1.1.1
# -----------------------------------------------------------------------------
set -euo pipefail

# ── Load defaults ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vars.sh
source "${SCRIPT_DIR}/vars.sh"

KEY_FILE=""
CERT_FILE=""

# ── Argument parsing ─────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [options]"
  echo "  --out-dir   <path>   Output directory              (default: ${OUT_DIR})"
  echo "  --cn        <name>   Certificate Common Name        (default: ${CERT_CN})"
  echo "  --org       <name>   Organisation                   (default: ${CERT_ORG})"
  echo "  --country   <cc>     Two-letter country code        (default: ${CERT_COUNTRY})"
  echo "  --days      <n>      Validity period in days        (default: ${CERT_DAYS})"
  echo "  --key-type  ec|rsa   Key algorithm                  (default: ${KEY_TYPE})"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)   OUT_DIR="$2";      shift 2 ;;
    --cn)        CERT_CN="$2";      shift 2 ;;
    --org)       CERT_ORG="$2";     shift 2 ;;
    --country)   CERT_COUNTRY="$2"; shift 2 ;;
    --days)      CERT_DAYS="$2";    shift 2 ;;
    --key-type)  KEY_TYPE="$2";     shift 2 ;;
    --help|-h)   usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
if ! command -v openssl &>/dev/null; then
  echo "ERROR: openssl is not installed or not in PATH." >&2
  exit 1
fi

if [[ "$KEY_TYPE" != "ec" && "$KEY_TYPE" != "rsa" ]]; then
  echo "ERROR: --key-type must be 'ec' or 'rsa'." >&2
  exit 1
fi

if [[ "$CERT_DAYS" -lt 1 || "$CERT_DAYS" -gt 7300 ]]; then
  echo "WARNING: CERT_DAYS=$CERT_DAYS is outside the recommended range (1–7300)."
fi

# ── Prepare output directory ─────────────────────────────────────────────────
mkdir -p "$OUT_DIR"

SAFE_CN="$(echo "$CERT_CN" | tr -- '- ' '_')"  # replace hyphens and spaces for filename safety
KEY_FILE="${OUT_DIR}/${SAFE_CN}.key.pem"
CERT_FILE="${OUT_DIR}/${SAFE_CN}.cert.pem"
CSR_FILE="$(mktemp)"

cleanup() { rm -f "$CSR_FILE"; }
trap cleanup EXIT

# Abort if outputs already exist to prevent accidental overwrite
for f in "$KEY_FILE" "$CERT_FILE"; do
  if [[ -e "$f" ]]; then
    echo "ERROR: Output file already exists: $f" >&2
    echo "       Delete it first or choose a different --out-dir / --cn." >&2
    exit 1
  fi
done

# ── Build Subject string ──────────────────────────────────────────────────────
SUBJECT="/CN=${CERT_CN}/O=${CERT_ORG}/OU=${CERT_OU}/C=${CERT_COUNTRY}"
[[ -n "$CERT_STATE"    ]] && SUBJECT+="/ST=${CERT_STATE}"
[[ -n "$CERT_LOCALITY" ]] && SUBJECT+="/L=${CERT_LOCALITY}"

# ── Generate private key ──────────────────────────────────────────────────────
echo "Generating $(echo "$KEY_TYPE" | tr '[:lower:]' '[:upper:]') private key..."
if [[ "$KEY_TYPE" == "ec" ]]; then
  openssl ecparam -genkey -name "$EC_CURVE" -noout -out "$KEY_FILE" 2>/dev/null
else
  openssl genrsa -out "$KEY_FILE" "$RSA_BITS" 2>/dev/null
fi
chmod 600 "$KEY_FILE"

# ── Generate CSR ──────────────────────────────────────────────────────────────
openssl req -new \
  -key "$KEY_FILE" \
  -subj "$SUBJECT" \
  -out "$CSR_FILE" 2>/dev/null

# ── X.509 extensions required for a trust anchor CA cert ─────────────────────
# CA:TRUE         — marks this as a CA certificate (mandatory for IAM RA)
# keyCertSign     — allows the cert to sign end-entity certs
# cRLSign         — allows CRL signing (best-practice for a CA)
# subjectKeyIdentifier / authorityKeyIdentifier — standard CA extensions
EXT=$(cat <<'EOF'
[v3_ca]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer:always
basicConstraints       = critical,CA:TRUE
keyUsage               = critical,keyCertSign,cRLSign
EOF
)

EXT_FILE="$(mktemp)"
trap "rm -f $CSR_FILE $EXT_FILE" EXIT
echo "$EXT" > "$EXT_FILE"

# ── Self-sign the certificate ─────────────────────────────────────────────────
echo "Signing certificate (CN=${CERT_CN}, valid ${CERT_DAYS} days)..."
openssl x509 -req \
  -days "$CERT_DAYS" \
  -in "$CSR_FILE" \
  -signkey "$KEY_FILE" \
  -extfile "$EXT_FILE" \
  -extensions v3_ca \
  -sha256 \
  -out "$CERT_FILE" 2>/dev/null
chmod 644 "$CERT_FILE"

# ── Verify the output ─────────────────────────────────────────────────────────
echo ""
echo "Certificate details:"
openssl x509 -in "$CERT_FILE" -noout \
  -subject -issuer -dates \
  -fingerprint -sha256
echo ""
echo "Extensions:"
openssl x509 -in "$CERT_FILE" -noout -text | grep -E -A 2 "Basic Constraints|Key Usage"

# =============================================================================
# Leaf certificate — signed by the CA above
# Used by aws_signing_helper in runner.sh
# =============================================================================
SAFE_ROLE="$(echo "$TA_ROLE_NAME" | tr -- '- ' '_')"
LEAF_KEY_FILE="${OUT_DIR}/${SAFE_ROLE}.key.pem"
LEAF_CERT_FILE="${OUT_DIR}/${SAFE_ROLE}.cert.pem"
LEAF_CSR_FILE="$(mktemp)"

for f in "$LEAF_KEY_FILE" "$LEAF_CERT_FILE"; do
  if [[ -e "$f" ]]; then
    echo "ERROR: Output file already exists: $f" >&2
    echo "       Delete it first or choose a different --out-dir / role name." >&2
    exit 1
  fi
done

echo ""
echo "Generating leaf certificate for role: ${TA_ROLE_NAME}..."

# Generate leaf private key (same algorithm as CA)
if [[ "$KEY_TYPE" == "ec" ]]; then
  openssl ecparam -genkey -name "$EC_CURVE" -noout -out "$LEAF_KEY_FILE" 2>/dev/null
else
  openssl genrsa -out "$LEAF_KEY_FILE" "$RSA_BITS" 2>/dev/null
fi
chmod 600 "$LEAF_KEY_FILE"

# Generate leaf CSR (same subject DN as CA, CN overridden to role name)
LEAF_SUBJECT="/CN=${TA_ROLE_NAME}/O=${CERT_ORG}/OU=${CERT_OU}/C=${CERT_COUNTRY}"
[[ -n "$CERT_STATE"    ]] && LEAF_SUBJECT+="/ST=${CERT_STATE}"
[[ -n "$CERT_LOCALITY" ]] && LEAF_SUBJECT+="/L=${CERT_LOCALITY}"

openssl req -new \
  -key "$LEAF_KEY_FILE" \
  -subj "$LEAF_SUBJECT" \
  -out "$LEAF_CSR_FILE" 2>/dev/null

# X.509 extensions for a leaf / end-entity certificate
# CA:FALSE        — must NOT be a CA cert
# digitalSignature — required for IAM Roles Anywhere client auth
# clientAuth      — extended key usage required by IAM Roles Anywhere
LEAF_EXT_FILE="$(mktemp)"
cat > "$LEAF_EXT_FILE" <<'EOF'
[v3_leaf]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature
extendedKeyUsage       = clientAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF

# Sign the leaf cert with the CA
openssl x509 -req \
  -days "$CERT_DAYS" \
  -in "$LEAF_CSR_FILE" \
  -CA "$CERT_FILE" -CAkey "$KEY_FILE" -CAcreateserial \
  -extfile "$LEAF_EXT_FILE" \
  -extensions v3_leaf \
  -sha256 \
  -out "$LEAF_CERT_FILE" 2>/dev/null
chmod 644 "$LEAF_CERT_FILE"

rm -f "$LEAF_CSR_FILE" "$LEAF_EXT_FILE"

echo ""
echo "Leaf certificate details:"
openssl x509 -in "$LEAF_CERT_FILE" -noout \
  -subject -issuer -dates \
  -fingerprint -sha256
echo ""
echo "Extensions:"
openssl x509 -in "$LEAF_CERT_FILE" -noout -text | grep -E -A 2 "Basic Constraints|Key Usage|Extended Key Usage"

# ── Summary ───────────────────────────────────────────────────────────────────
# cat <<EOF

# Done.
#   CA certificate : $CERT_FILE       (upload to IAM Roles Anywhere Trust Anchor)
#   CA private key : $KEY_FILE        (keep secret — only needed to sign leaf certs)

#   Leaf certificate : $LEAF_CERT_FILE  (used by aws_signing_helper in runner.sh)
#   Leaf private key : $LEAF_KEY_FILE   (keep secret — used by runner.sh at runtime)

# CERT_CN in scripts/vars.sh must remain: ${CERT_CN}
# runner.sh derives the leaf cert/key paths from TA_ROLE_NAME: ${TA_ROLE_NAME}

# To upload the CA certificate as a Trust Anchor:
#   aws rolesanywhere create-trust-anchor \\
#     --name "${CERT_CN}" \\
#     --source '{"sourceType":"CERTIFICATE_BUNDLE","sourceData":{"x509CertificateData":"'"$(openssl x509 -in "$CERT_FILE" -outform PEM | awk '{printf "%s\\n", $0}')"'"}}' \\
#     --enabled \\
#     --region ${AWS_REGION}
# EOF

# EOF