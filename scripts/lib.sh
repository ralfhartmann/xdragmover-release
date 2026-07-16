#!/usr/bin/env bash
# Shared helpers for scripts/package.sh, scripts/install.sh,
# scripts/uninstall.sh and scripts/make_dmg.sh. Not meant to be run
# directly — source it instead.

APP_PROCESS_NAME="XDragMover"
APP_BUNDLE_NAME="XDragMover.app"

# Quits a currently running copy of the app, if any. Best-effort: if the
# app doesn't respond in time, the caller (install/uninstall) still
# proceeds regardless. NSApplication handles the standard Quit Apple Event
# automatically, so this works even though the app has no Dock icon/menu
# bar in normal (non-debug) use.
#
# Both install and uninstall need this: overwriting or removing the bundle
# of a running app can fail outright, or leave the running process pointing
# at now-deleted files on disk.
quit_app_if_running() {
  if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
    echo "Quitting the currently running $APP_PROCESS_NAME ..."
    osascript -e "tell application \"$APP_PROCESS_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
  fi
}

# Builds the Release configuration into $1 (a fresh, empty directory) and
# fails loudly if XDragMover.app doesn't end up there. Shared by
# package.sh and make_dmg.sh so both produce the same, identically-signed
# app bundle the same way.
build_release_app() {
  local build_dir="$1"
  echo "Building Release configuration into $build_dir ..."
  # Deliberately just 'build', not 'clean build': $build_dir is a brand new
  # directory from mktemp on every run, so there's nothing to clean — and
  # Xcode's build system refuses to run 'clean' against a directory it
  # didn't create itself ("Could not delete ... because it was not created
  # by the build system"), which made this step fail outright.
  #
  # No CODESIGN_OVERRIDES here on purpose: this must be signed with a real
  # Team identity (see package.sh's header comment), so it deliberately
  # does NOT disable code signing the way build/test do.
  xcodebuild \
    -project "XDragMover.xcodeproj" \
    -scheme "XDragMover" \
    -configuration Release \
    -destination 'platform=macOS' \
    CONFIGURATION_BUILD_DIR="$build_dir" \
    build

  if [[ ! -d "$build_dir/$APP_BUNDLE_NAME" ]]; then
    echo "error: build did not produce $build_dir/$APP_BUNDLE_NAME" >&2
    exit 1
  fi
}

# Notarizes and staples the signed .app or .dmg at $1, in place. Shared by
# package.sh (the .app) and make_dmg.sh (both the .app before assembling
# the .dmg, and the finished .dmg itself — stapling the .dmg too lets
# Gatekeeper accept it the moment it's opened/mounted, without needing a
# network check at that point, not just after the app is dragged out).
#
# Requires a Developer ID Application signature already on $1 (Automatic/
# free Apple Development signing isn't accepted for notarization) — see
# project.pbxproj's Release configuration and DEVELOPMENT.md's
# "Notarization" section for how that's set up.
#
# Auth: prefers the three NOTARY_API_KEY_PATH/NOTARY_API_KEY_ID/
# NOTARY_API_ISSUER env vars (set by CI from decoded secrets — see
# build-dmg.yml) over a local keychain profile, so CI never depends on a
# machine-local keychain item existing. Locally, falls back to a
# `xcrun notarytool store-credentials` profile named
# $NOTARY_KEYCHAIN_PROFILE (default "xdragmover-notary") — see
# DEVELOPMENT.md for how to create it.
notarize_and_staple() {
  local target_path="$1"

  local notary_auth_args
  if [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER:-}" ]]; then
    notary_auth_args=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER")
  else
    notary_auth_args=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-xdragmover-notary}")
  fi

  # notarytool only accepts a zip/dmg/pkg for submission, never a bare
  # .app directly — zip it into a throwaway temp file purely for the
  # upload. Stapling afterwards applies directly to $target_path itself
  # (the original .app or .dmg), which is what actually needs to carry
  # the ticket.
  local submission_dir submission_zip
  submission_dir="$(mktemp -d)"
  submission_zip="$submission_dir/$(basename "$target_path").zip"
  ditto -c -k --keepParent "$target_path" "$submission_zip"

  echo "Submitting $(basename "$target_path") for notarization (can take a few minutes) ..."
  xcrun notarytool submit "$submission_zip" "${notary_auth_args[@]}" --wait

  echo "Stapling notarization ticket to $(basename "$target_path") ..."
  xcrun stapler staple "$target_path"

  rm -rf "$submission_dir"
}
