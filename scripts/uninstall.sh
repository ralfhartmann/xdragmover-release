#!/usr/bin/env bash
# Removes /Applications/XDragMover.app, quitting a running copy first
# if needed (see scripts/lib.sh's quit_app_if_running — same reasoning as
# scripts/install.sh: removing a running app's bundle out from under it can
# behave unpredictably).
#
# Note: this does not un-register "Start at Login" (SMAppService) if it was
# enabled — that has to be done by the app itself while it's still
# installed, e.g. by toggling the menu bar item's "Start at Login" off
# before uninstalling.
#
# Usage: scripts/uninstall.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"

INSTALL_PATH="/Applications/$APP_BUNDLE_NAME"

quit_app_if_running

if [[ ! -d "$INSTALL_PATH" ]]; then
  echo "$INSTALL_PATH does not exist; nothing to uninstall."
  exit 0
fi

echo "Removing $INSTALL_PATH ..."
rm -rf "$INSTALL_PATH"
echo "Uninstalled $INSTALL_PATH."
