#!/usr/bin/env bash
# Builds dist/FluxBar.app, dist/FluxBar.zip (for the curl installer) and dist/FluxBar.dmg.
#
#   scripts/build-app.sh                 # native arch, ad-hoc signed
#   UNIVERSAL=1 scripts/build-app.sh     # arm64 + x86_64 (needs Xcode, used in CI)
#
# Optional, for a smooth Gatekeeper experience with the .dmg:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="fluxbar"   # created once with: xcrun notarytool store-credentials fluxbar
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/ClipCore/FluxBarInfo.swift)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUNDLE_ID="com.fluxbar.FluxBar"
DIST="$ROOT/dist"
APP="$DIST/FluxBar.app"
PRODUCTS=(FluxBar flux clip com.fluxbar.powerd)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

[ -n "$VERSION" ] || { echo "Could not read version from FluxBarInfo.swift" >&2; exit 1; }

# ---------------------------------------------------------------- build
say "Building FluxBar $VERSION ($BUILD_NUMBER)"
SWIFT_FLAGS=(-c release -Xswiftc -Osize)
if [ "${UNIVERSAL:-0}" = "1" ]; then
  SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi
for p in "${PRODUCTS[@]}"; do
  swift build "${SWIFT_FLAGS[@]}" --product "$p"
done
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

# ---------------------------------------------------------------- bundle
say "Assembling FluxBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for p in "${PRODUCTS[@]}"; do
  cp "$BIN/$p" "$APP/Contents/MacOS/$p"
  strip -x "$APP/Contents/MacOS/$p" 2>/dev/null || true
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>FluxBar</string>
  <key>CFBundleExecutable</key><string>FluxBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FluxBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>FluxBar</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# ---------------------------------------------------------------- sign
IDENTITY="${SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
  say "Signing with $IDENTITY"
else
  say "Ad-hoc signing (set SIGN_IDENTITY for Developer ID)"
fi
# Inner executables first, then the bundle.
for p in flux clip com.fluxbar.powerd; do
  codesign "${SIGN_ARGS[@]}" --identifier "com.fluxbar.$p" "$APP/Contents/MacOS/$p"
done
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

# ---------------------------------------------------------------- zip (curl installer)
say "Creating FluxBar.zip"
rm -f "$DIST/FluxBar.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FluxBar.zip"

if [ "$IDENTITY" != "-" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  say "Notarizing app"
  xcrun notarytool submit "$DIST/FluxBar.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$DIST/FluxBar.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FluxBar.zip"
fi

# ---------------------------------------------------------------- dmg
say "Creating FluxBar.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/FluxBar.dmg"
hdiutil create -quiet -volname "FluxBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DIST/FluxBar.dmg"
if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DIST/FluxBar.dmg"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    say "Notarizing dmg"
    xcrun notarytool submit "$DIST/FluxBar.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DIST/FluxBar.dmg"
  fi
fi

# ---------------------------------------------------------------- checksums
( cd "$DIST" && shasum -a 256 FluxBar.zip > FluxBar.zip.sha256 && shasum -a 256 FluxBar.dmg > FluxBar.dmg.sha256 )

say "Done"
du -sh "$APP" "$DIST/FluxBar.zip" "$DIST/FluxBar.dmg" | sed 's/^/    /'
