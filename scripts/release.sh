#!/usr/bin/env bash
# Cuts a release from the 'dev' branch, per DEVELOPMENT.md:
#   1. Run the full test suite.
#   2. Pause for a manual README.md review/update.
#   3. Bump VERSION.md (and the Xcode project's MARKETING_VERSION).
#   4. Merge dev into main and tag the release.
#   5. Build an installation package.
#
# Usage: scripts/release.sh [major|minor|patch]
#   Default bump type: patch
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP="${1:-patch}"

echo "==> [1/5] Checking preconditions"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is not clean. Commit or stash changes before releasing." >&2
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "dev" ]]; then
  echo "error: release must be run from the 'dev' branch (currently on '$current_branch')." >&2
  exit 1
fi

echo "==> [2/5] Running full test suite"
make test

echo "==> [3/5] README.md review"
echo "    If this release needs documentation changes, edit and save README.md now"
echo "    (in another terminal/editor), then come back here."
read -r -p "    Press Enter once README.md is up to date to continue (Ctrl-C to abort) ... " _

if [[ -n "$(git status --porcelain -- README.md)" ]]; then
  git add README.md
  git commit -m "Update README.md for release"
fi

echo "==> [4/5] Bumping version ($BUMP)"
./scripts/bump_version.sh "$BUMP"
NEW_VERSION="$(tr -d '[:space:]' < VERSION.md)"
git add VERSION.md XDragMover.xcodeproj/project.pbxproj
git commit -m "Bump version to $NEW_VERSION"

echo "==> [5/5] Merging dev into main, tagging, and packaging"
git checkout main
git merge --no-ff dev -m "Release $NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "Release $NEW_VERSION"
git checkout dev

./scripts/package.sh "$NEW_VERSION"

cat <<EOF

Release $NEW_VERSION complete.
  - main now points at the merge commit for this release (tagged v$NEW_VERSION).
  - dev continues unchanged, ready for the next feature/bugfix branch.
  - Installation package: dist/XDragMover-$NEW_VERSION.zip
  - Remember to push, if you use a remote: git push origin main dev --tags
EOF
