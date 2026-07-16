#!/usr/bin/env bash
# Bumps the semantic version stored in VERSION.md (major.minor.patch) and
# keeps the Xcode project's MARKETING_VERSION build settings in sync.
#
# Usage: scripts/bump_version.sh [major|minor|patch]
#   Default: patch
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION_FILE="VERSION.md"
PBXPROJ="XDragMover.xcodeproj/project.pbxproj"
BUMP="${1:-patch}"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: $VERSION_FILE not found" >&2
  exit 1
fi

current="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "error: $VERSION_FILE does not contain a valid semantic version (found: '$current')" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$BUMP" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *)
    echo "error: unknown bump type '$BUMP' (expected: major, minor, or patch)" >&2
    exit 1
    ;;
esac

new="$major.$minor.$patch"
printf '%s\n' "$new" > "$VERSION_FILE"

# Keep the Xcode project's MARKETING_VERSION (CFBundleShortVersionString) in
# sync with VERSION.md so the built app reports the same version.
if [[ -f "$PBXPROJ" ]]; then
  sed -i.bak "s/MARKETING_VERSION = ${current};/MARKETING_VERSION = ${new};/g" "$PBXPROJ"
  rm -f "${PBXPROJ}.bak"
fi

echo "Bumped version: $current -> $new"
