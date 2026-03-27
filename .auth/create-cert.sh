#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-cert.sh
# Generates a self-signed CA certificate suitable for use as an
# AWS IAM Roles Anywhere Trust Anchor.
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

# ── Summary ───────────────────────────────────────────────────────────────────
cat <<EOF

Done.
  Private key : $KEY_FILE   (keep secret — never upload this)
  Certificate : $CERT_FILE  (upload this to IAM Roles Anywhere)

To upload the certificate as a Trust Anchor:
  aws rolesanywhere create-trust-anchor \\
    --name "${CERT_CN}" \\
    --source '{"sourceType":"CERTIFICATE_BUNDLE","sourceData":{"x509CertificateData":"'"$(openssl x509 -in "$CERT_FILE" -outform PEM | awk '{printf "%s\\n", $0}')"'"}}' \\
    --enabled \\
    --region <your-region>

EOF