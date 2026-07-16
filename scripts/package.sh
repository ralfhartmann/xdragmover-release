#!/usr/bin/env bash
# Builds a Release configuration of XDragMover, notarizes and staples it,
# and packages the .app into a zip archive under dist/.
#
# Usage: scripts/package.sh [version]
#   Default version: contents of VERSION.md
#
# Signing: uses a "Developer ID Application" identity (CODE_SIGN_STYLE =
# Manual, CODE_SIGN_IDENTITY = "Developer ID Application", set in
# project.pbxproj's Release configuration) under whatever Team is
# configured in Xcode on this machine. This is the same kind of real,
# Apple-issued identity carrying a genuine Team Identifier that an earlier
# free "Apple Development" identity already provided for stable
# Accessibility-permission recognition across rebuilds — see
# DEVELOPMENT.md's "Notarization" section for why a Developer ID
# specifically (not just Apple Development) is required for what comes
# next: this is also the only identity type Apple's notary service
# accepts for notarization, and notarization plus stapling (below) is what
# actually removes Gatekeeper's "unidentified developer" warning on a
# machine that has never run this app before, which a signature alone
# (of either identity type) does not.
#
# Requires a Team selected in Xcode (Settings -> Accounts, then the
# project's Signing & Capabilities tab) on whatever machine runs this
# script, same as 'make run'/'make debug', plus notarization credentials
# — see lib.sh's notarize_and_staple and DEVELOPMENT.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"

DIST_DIR="dist"
VERSION="${1:-$(tr -d '[:space:]' < VERSION.md)}"

mkdir -p "$DIST_DIR"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

build_release_app "$BUILD_DIR"
APP_PATH="$BUILD_DIR/$APP_BUNDLE_NAME"

notarize_and_staple "$APP_PATH"

ARCHIVE_PATH="$DIST_DIR/XDragMover-${VERSION}.zip"
echo "Packaging $APP_PATH -> $ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

echo "Created installation package: $ARCHIVE_PATH"
