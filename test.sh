#!/usr/bin/env bash
set -euo pipefail

# Where to stash the binary
BIN_PATH="${HOME}/.gitleaks"
VERSION="${GITLEAKS_VERSION:-8.27.2}"

# Get checked out repository
echo "Getting checked out repository…"

#get git branch name, commit hash, and commit message, author name, author email, and date
BRANCH_NAME=$(git branch --show-current)
COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_MESSAGE=$(git log -1 --pretty=%B)
AUTHOR_NAME=$(git log -1 --pretty=%an)
AUTHOR_EMAIL=$(git log -1 --pretty=%ae)
DATE=$(git log -1 --pretty=%ad)
echo "Branch name: $BRANCH_NAME"
echo "Commit hash: $COMMIT_HASH"
echo "Commit message: $COMMIT_MESSAGE"
echo "Author name: $AUTHOR_NAME"
echo "Author email: $AUTHOR_EMAIL"
echo "Date: $DATE"

# Detect OS & ARCH for the release asset
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then ARCH="x64"; fi
if [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi

# Download & unpack on cache miss
if [[ ! -x "$BIN_PATH/gitleaks" ]]; then
  echo "Downloading gitleaks $VERSION for $OS/$ARCH…"
  DOWNLOAD_URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
  echo "Download URL: $DOWNLOAD_URL"
  mkdir -p "$BIN_PATH"
  
  # Download with more verbose output and error checking
  if ! curl -fsSL \
    "$DOWNLOAD_URL" \
    | tar -xz -C "$BIN_PATH"; then
    echo "Error: Failed to download or extract gitleaks binary"
    exit 1
  fi
  
  #remove all files except gitleaks if exists
  mv "$BIN_PATH/gitleaks" ../
  rm -rf "$BIN_PATH/*"
  mv ../gitleaks "$BIN_PATH/gitleaks"

  # Verify the binary exists and is executable
  if [[ ! -x "$BIN_PATH/gitleaks" ]]; then
    echo "Error: Binary not found or not executable at $BIN_PATH/gitleaks"
    exit 1
  fi
fi

# Run the scan against the current directory
echo "Running gitleaks detect…"
echo "Binary location: $BIN_PATH"
ls "$BIN_PATH"

"$BIN_PATH/gitleaks" dir . \
  --report-format json \
  --report-path gitleaks-report.json \
  --no-banner \
  --max-target-megabytes 1

echo "Scan complete. Report at gitleaks-report.json"

# Print the report
cat gitleaks-report.json
rm gitleaks-report.json