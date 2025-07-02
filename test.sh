#!/usr/bin/env bash
set -euo pipefail

# Where to stash the binary
CACHE_DIR="${HOME}/.gitleaks"
VERSION="${GITLEAKS_VERSION:-8.27.2}"

# Get checked out repository
echo "Getting checked out repository…"

# Detect OS & ARCH for the release asset
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then ARCH="x64"; fi
if [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi

# Path to the binary inside the cache - simplified
BIN_PATH="${CACHE_DIR}/gitleaks"

# Download & unpack on cache miss
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Downloading gitleaks $VERSION for $OS/$ARCH…"
  DOWNLOAD_URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
  echo "Download URL: $DOWNLOAD_URL"
  mkdir -p "$CACHE_DIR"
  
  # Download with more verbose output and error checking
  if ! curl -fsSL \
    "$DOWNLOAD_URL" \
    | tar -xz -C "$CACHE_DIR"; then
    echo "Error: Failed to download or extract gitleaks binary"
    exit 1
  fi
  
  #remove the tar.gz file
  rm gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz
  
  # Verify the binary exists and is executable
  if [[ ! -x "$BIN_PATH" ]]; then
    echo "Error: Binary not found or not executable at $BIN_PATH"
    exit 1
  fi
fi

# Run the scan against the current directory
echo "Running gitleaks detect…"

echo "BIN_PATH: $BIN_PATH"
ls $CACHE_DIR

"$BIN_PATH" git . \
  --report-format json \
  --report-path gitleaks-report.json

echo "Scan complete. Report at gitleaks-report.json"

# Print the report
cat gitleaks-report.json
rm gitleaks-report.json