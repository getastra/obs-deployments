#!/usr/bin/env bash
set -euo pipefail

# Where to stash the binary
CACHE_DIR="${HOME}/.gitleaks"
VERSION="${GITLEAKS_VERSION:-v8.25.0}"

# Get checked out repository
echo "Getting checked out repository…"
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
  echo "Downloading gitleaks $VERSION for $OS/$ARCH…"
  # https://github.com/gitleaks/gitleaks/releases/download/v8.25.0/gitleaks_8.25.0_darwin_arm64.tar.gz
  DOWNLOAD_URL="https://github.com/gitleaks/gitleaks/releases/download/${VERSION}/gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
  echo "Download URL: $DOWNLOAD_URL"
  mkdir -p "$BIN_DIR"
  
  # Download with more verbose output and error checking
  if ! curl -fsSL --verbose \
    "$DOWNLOAD_URL" \
    | tar -xz -C "$BIN_DIR"; then
    echo "Error: Failed to download or extract gitleaks binary"
    echo "Please check if the version $VERSION is available for $OS/$ARCH at:"
    echo "https://github.com/gitleaks/gitleaks/releases"
    exit 1
  fi
  
  # Verify the binary exists and is executable
  if [[ ! -x "$BIN_PATH" ]]; then
    echo "Error: Binary not found or not executable at $BIN_PATH"
    exit 1
  fi
fi

# Run the scan against the current directory
echo "Running gitleaks detect…"
"$BIN_PATH" detect \
  --source . \
  --config gitleaks.toml \
  --report-format json

echo "Scan complete. Report at gitleaks-report.json"