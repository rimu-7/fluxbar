#!/usr/bin/env bash
# Exercise Finder's install path: mount read-only, copy out, then launch the copied bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:-$ROOT/dist/FluxBar.dmg}"
WORK="$(mktemp -d)"
MOUNT="$WORK/mounted"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$MOUNT" "$WORK/Applications With Spaces"
hdiutil verify "$DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
test "$(readlink "$MOUNT/Applications")" = /Applications
test -s "$MOUNT/Install FluxBar.txt"
APP="$WORK/Applications With Spaces/FluxBar.app"
ditto "$MOUNT/FluxBar.app" "$APP"
bash "$ROOT/scripts/verify-app.sh" "$APP"
