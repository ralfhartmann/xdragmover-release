#!/usr/bin/env bash
# Builds a package (see scripts/package.sh) and installs it into
# /Applications, replacing any existing copy.
#
# Usage: scripts/install.sh [version]
#   Default version: contents of VERSION.md (same default as package.sh)
#
# This exists because a build that stays outside /Applications is exactly
# the "unstable location" that causes real, hard-to-diagnose problems for
# this app specifically: App Translocation (Gatekeeper relaunches a
# quarantined app from a random path on every launch, see DEVELOPMENT.md)
# and SMAppService's "Start at Login" feature both require a stable,
# installed location, not a build/ folder or a still-zipped download.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"

VERSION="${1:-$(tr -d '[:space:]' < VERSION.md)}"
DIST_DIR="dist"
ARCHIVE_PATH="$DIST_DIR/XDragMover-${VERSION}.zip"
INSTALL_PATH="/Applications/$APP_BUNDLE_NAME"

echo "Building package for version $VERSION ..."
./scripts/package.sh "$VERSION"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "error: expected package not found at $ARCHIVE_PATH" >&2
  exit 1
fi

EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT

echo "Unzipping $ARCHIVE_PATH ..."
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"

if [[ ! -d "$EXTRACT_DIR/$APP_BUNDLE_NAME" ]]; then
  echo "error: $APP_BUNDLE_NAME not found inside $ARCHIVE_PATH" >&2
  exit 1
fi

quit_app_if_running

if [[ -d "$INSTALL_PATH" ]]; then
  echo "Removing existing $INSTALL_PATH ..."
  rm -rf "$INSTALL_PATH"
fi

echo "Installing to $INSTALL_PATH ..."
ditto "$EXTRACT_DIR/$APP_BUNDLE_NAME" "$INSTALL_PATH"

echo "Installed $INSTALL_PATH (version $VERSION)."
echo "On first launch you may still need to approve it once via System Settings > Privacy & Security (Gatekeeper) and grant Accessibility access."
