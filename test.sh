#!/usr/bin/env bash
set -euo pipefail

# Where to stash the binary
CACHE_DIR="${HOME}/.gitleaks"
VERSION="${GITLEAKS_VERSION:-v8.25.0}"

# Get checked out repository
echo "🔍  Getting checked out repository…"
ls -ltr /
pwd

# Detect OS & ARCH for the release asset
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then ARCH="amd64"; fi
if [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi

# Path to the binary inside the cache
BIN_DIR="${CACHE_DIR}/gitleaks_${VERSION}_${OS}_${ARCH}"
BIN_PATH="${BIN_DIR}/gitleaks"

# Download & unpack on cache miss
if [[ ! -x "$BIN_PATH" ]]; then
  echo "⬇️  Downloading gitleaks $VERSION for $OS/$ARCH…"
  mkdir -p "$BIN_DIR"
  curl -sL \
    "https://github.com/gitleaks/gitleaks/releases/download/${VERSION}/gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz" \
    | tar -xz -C "$BIN_DIR"
fi

# Run the scan against the current directory
echo "🔍  Running gitleaks detect…"
"$BIN_PATH" detect \
  --source . \
  --config gitleaks.toml \
  --report-format json

echo "✅  Scan complete. Report at gitleaks-report.json"