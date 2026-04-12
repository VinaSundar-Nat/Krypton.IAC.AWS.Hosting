#!/usr/bin/env bash
# =============================================================================
# install-deps.sh
# Installs tooling dependencies required by the runner scripts.
#
# NOTE: Package manager auto-install is supported on:
#   - macOS    (Homebrew)
#   - Debian / Ubuntu  (apt-get)
#   - RHEL / Amazon Linux / Fedora  (yum / dnf)
#   - Alpine Linux  (apk)
#   - Any Linux / CI without a package manager → static binary via curl
#
# For all other operating systems, tools must be installed manually.
# =============================================================================
set -euo pipefail

# ── yq ────────────────────────────────────────────────────────────────────────
# https://github.com/mikefarah/yq
# Used by replace-vars.sh to parse environment YAML files.
if ! command -v yq &>/dev/null; then
  echo "yq not found — installing..."

  OS="$(uname -s)"

  case "${OS}" in

    Darwin)
      # ── macOS — requires Homebrew (https://brew.sh) ──────────────────────
      if command -v brew &>/dev/null; then
        brew install yq
      else
        echo "ERROR: Homebrew not found. Install it from https://brew.sh then re-run." >&2
        exit 1
      fi
      ;;

    Linux)
      # ── Detect Linux package manager, fall back to static binary ─────────
      if command -v apt-get &>/dev/null; then
        # Debian / Ubuntu
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends yq

      elif command -v dnf &>/dev/null; then
        # Fedora / RHEL 8+ / Amazon Linux 2023
        sudo dnf install -y yq

      elif command -v yum &>/dev/null; then
        # RHEL 7 / Amazon Linux 2 — yq not in default repos, use binary
        _install_yq_binary

      elif command -v apk &>/dev/null; then
        # Alpine Linux (common in CI containers)
        sudo apk add --no-cache yq

      else
        # No known package manager — download static binary
        _install_yq_binary
      fi
      ;;

    *)
      echo "ERROR: Unsupported OS '${OS}'. Install yq manually: https://github.com/mikefarah/yq" >&2
      exit 1
      ;;
  esac

  echo "yq $(yq --version) ready."
fi

# ── Helper: install yq static binary to ~/.local/bin ─────────────────────────
_install_yq_binary() {
  local YQ_VERSION="v4.44.3"
  local YQ_ARCH
  YQ_ARCH="$(uname -m)"
  case "${YQ_ARCH}" in
    x86_64)        YQ_ARCH="amd64" ;;
    aarch64|arm64) YQ_ARCH="arm64" ;;
    armv7l)        YQ_ARCH="arm" ;;
    *)
      echo "ERROR: Unsupported architecture '${YQ_ARCH}' for yq binary install." >&2
      exit 1
      ;;
  esac

  local YQ_OS
  YQ_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local YQ_BIN="${HOME}/.local/bin/yq"
  mkdir -p "$(dirname "${YQ_BIN}")"

  echo "Downloading yq ${YQ_VERSION} (${YQ_OS}/${YQ_ARCH}) → ${YQ_BIN}"
  curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${YQ_OS}_${YQ_ARCH}" \
    -o "${YQ_BIN}"
  chmod u+x "${YQ_BIN}"
  export PATH="${HOME}/.local/bin:${PATH}"
  echo "yq installed to ${YQ_BIN}"
}
