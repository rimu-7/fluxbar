#!/usr/bin/env bash
# Check the distributed bundle, without installing helpers or changing user settings.
set -euo pipefail

APP="${1:?Usage: verify-app.sh /path/to/FluxBar.app}"
codesign --verify --deep --strict "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = com.fluxbar.FluxBar
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = true
test -s "$APP/Contents/Resources/AppIcon.icns"
test -d "$APP/Contents/Resources/GRDB_GRDB.bundle"
for binary in FluxBar flux clip com.fluxbar.powerd; do
  test -x "$APP/Contents/MacOS/$binary"
  # A developer-machine library path would make a copied DMG fail on another Mac.
  DEPENDENCIES="$(otool -L "$APP/Contents/MacOS/$binary" | tail -n +2)"
  while read -r dependency _; do
    case "$dependency" in
      /System/*|/usr/lib/*|@rpath/*|@executable_path/*|@loader_path/*) ;;
      *) echo "Unexpected external dependency in $binary: $dependency" >&2; exit 1 ;;
    esac
  done <<< "$DEPENDENCIES"
done
"$APP/Contents/MacOS/FluxBar" --check-installation
"$APP/Contents/MacOS/flux" --version
"$APP/Contents/MacOS/clip" --help >/dev/null
"$APP/Contents/MacOS/com.fluxbar.powerd" >/dev/null
