#!/usr/bin/env bash
# Builds a .dmg installer for XDragMover: mounting it shows a Finder
# window with the app icon next to a shortcut to /Applications (plus a
# small generated background graphic pointing from one to the other), so
# installing is just "drag the app onto Applications" — the standard macOS
# drag-to-install UX. No extra tooling required beyond Xcode's command
# line tools (hdiutil, osascript, swift are all part of it).
#
# Usage: scripts/make_dmg.sh [version]
#   Default version: contents of VERSION.md (same default as package.sh)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"

VERSION="${1:-$(tr -d '[:space:]' < VERSION.md)}"
DIST_DIR="dist"
VOLUME_NAME="XDragMover"
FINAL_DMG="$DIST_DIR/XDragMover-${VERSION}.dmg"
WINDOW_WIDTH=660
WINDOW_HEIGHT=400

mkdir -p "$DIST_DIR"
rm -f "$FINAL_DMG"

BUILD_DIR="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"
RW_DMG_DIR="$(mktemp -d)"
RW_DMG="$RW_DMG_DIR/rw.dmg"
# Deliberately NOT a custom -mountpoint (e.g. under a mktemp dir): Finder's
# "disk" scripting object only resolves volumes mounted the normal way,
# under /Volumes. A custom mountpoint elsewhere mounts the filesystem just
# fine, but Finder never learns about it as a browsable disk, so the
# `tell application "Finder" to ... disk "$VOLUME_NAME"` step below failed
# outright ("Can't get disk ... (-1728)") regardless of how long it waited.
MOUNT_DIR="/Volumes/$VOLUME_NAME"

cleanup() {
  # Best-effort: if it's already detached (or was never attached), this
  # just fails quietly, which is fine during cleanup.
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  rm -rf "$BUILD_DIR" "$STAGING_DIR" "$RW_DMG_DIR"
}
trap cleanup EXIT

# Defensively clear out any stale mount left over from an earlier,
# interrupted run under this same volume name.
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

build_release_app "$BUILD_DIR"
notarize_and_staple "$BUILD_DIR/$APP_BUNDLE_NAME"

echo "Assembling DMG contents in $STAGING_DIR ..."
ditto "$BUILD_DIR/$APP_BUNDLE_NAME" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir "$STAGING_DIR/.background"
echo "Generating background image ..."
swift "$ROOT_DIR/scripts/generate_dmg_background.swift" \
  "$STAGING_DIR/.background/background.png" "$WINDOW_WIDTH" "$WINDOW_HEIGHT"

echo "Creating writable disk image ..."
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDRW "$RW_DMG" >/dev/null

echo "Mounting it to arrange the Finder window ..."
# Deliberately NOT -nobrowse: that flag hides the volume from Finder
# entirely, which then makes `tell application "Finder" to ... disk
# "$VOLUME_NAME"` below fail with "Can't get disk ... (-1728)", since
# Finder genuinely doesn't know about a -nobrowse-mounted volume.
hdiutil attach "$RW_DMG" -quiet

# Finder can take a brief moment to notice a just-mounted volume even
# though the filesystem is already available at $MOUNT_DIR; scripting it
# too early reproduces the same "Can't get disk" error. Poll instead of a
# single fixed sleep, so this is both fast on the common case and
# tolerant of a slower machine.
echo "Waiting for Finder to notice the volume ..."
for _ in $(seq 1 20); do
  if osascript -e "tell application \"Finder\" to exists disk \"$VOLUME_NAME\"" 2>/dev/null | grep -qi true; then
    break
  fi
  sleep 0.5
done

# Lays out the window exactly like the popular (but external) `create-dmg`
# tool does, without depending on it: icon view, no toolbar/status bar, a
# fixed window size, free (non-grid) icon arrangement so explicit positions
# stick, the generated background picture, and the app/Applications icons
# placed left/right of the arrow drawn into that picture.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, $((WINDOW_WIDTH + 100)), $((WINDOW_HEIGHT + 100))}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_BUNDLE_NAME" of container window to {160, 190}
    set position of item "Applications" of container window to {$((WINDOW_WIDTH - 160)), 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_DIR" -quiet

echo "Converting to compressed, read-only image ..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

# The .dmg container itself needs its own Developer ID signature — separate
# from the .app's signature already inside it — for Gatekeeper to accept
# it the moment it's opened/mounted (checked via `spctl --type open`, not
# the `--type execute` check the stapled .app alone satisfies). Signing
# must happen *before* notarizing/stapling below: notarizing an unsigned
# .dmg is accepted by Apple's notary service, but then signing it
# afterwards invalidates that staple (a code signature applied after the
# fact changes the very hash the ticket was issued for), so the order here
# is deliberate — sign, then notarize, then staple.
echo "Signing the .dmg itself ..."
# Full path deliberately, not a bare 'codesign': live-reproduced on the
# GitLab Runner, whose non-interactive LaunchAgent PATH resolved a
# different, unrelated 'codesign'-named binary ahead of Apple's real one
# at /usr/bin/codesign, failing with "The following argument was not
# expected: --timestamp" — a parse-error style Apple's own codesign
# doesn't produce. This sidesteps that regardless of what else is
# installed/ordered on a given runner's PATH.
/usr/bin/codesign --sign "Developer ID Application" --timestamp "$FINAL_DMG"

# Notarizing/stapling the .dmg itself too (not just the .app already
# stapled above) lets Gatekeeper accept it the moment it's opened/mounted,
# without needing a network check at that point.
notarize_and_staple "$FINAL_DMG"

echo "Created installer: $FINAL_DMG"
