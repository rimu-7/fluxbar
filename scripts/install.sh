#!/bin/bash
# FluxBar installer
#
#   curl -fsSL https://raw.githubusercontent.com/rimu-7/fluxbar/main/scripts/install.sh | bash
#
# Options (pass after `bash -s --`):
#   --version X.Y.Z   install a specific release (default: latest)
#   --dir PATH        where to put FluxBar.app (default: /Applications, or ~/Applications)
#   --bin-dir PATH    where to link the `flux` and `clip` commands
#   --no-launch       don't open FluxBar after installing
#   --uninstall       remove FluxBar, its commands and the battery helper (keeps your clipboard history)
#   --purge           with --uninstall, also delete clipboard history and settings
#
# Environment: FLUXBAR_REPO=owner/repo, FLUXBAR_ZIP=/local/FluxBar.zip (offline / testing)
set -euo pipefail

REPO="${FLUXBAR_REPO:-rimu-7/fluxbar}"
VERSION="latest"
APP_DIR=""
BIN_DIR=""
LAUNCH=1
UNINSTALL=0
PURGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="${2#v}"; shift 2 ;;
    --dir)       APP_DIR="$2"; shift 2 ;;
    --bin-dir)   BIN_DIR="$2"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge)     PURGE=1; shift ;;
    -h|--help)   sed -n '2,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "FluxBar runs on macOS only."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 13 ] || die "FluxBar needs macOS 13 Ventura or newer."

writable_dir() { [ -d "$1" ] && [ -w "$1" ]; }

pick_app_dir() {
  if [ -n "$APP_DIR" ]; then mkdir -p "$APP_DIR"; return; fi
  if writable_dir /Applications; then APP_DIR=/Applications
  else APP_DIR="$HOME/Applications"; mkdir -p "$APP_DIR"; fi
}

pick_bin_dir() {
  if [ -n "$BIN_DIR" ]; then mkdir -p "$BIN_DIR"; return; fi
  for d in /opt/homebrew/bin /usr/local/bin; do
    if writable_dir "$d" && [[ ":$PATH:" == *":$d:"* ]]; then BIN_DIR="$d"; return; fi
  done
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
}

quit_running_app() {
  if pgrep -xq FluxBar; then
    info "Quitting running FluxBar"
    osascript -e 'quit app id "com.fluxbar.FluxBar"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq FluxBar || break; sleep 0.3; done
    pkill -x FluxBar 2>/dev/null || true
  fi
}

find_installed_app() {
  for d in "$APP_DIR" /Applications "$HOME/Applications"; do
    [ -n "$d" ] && [ -d "$d/FluxBar.app" ] && { echo "$d/FluxBar.app"; return; }
  done
}

# ------------------------------------------------------------------ uninstall
if [ "$UNINSTALL" = 1 ]; then
  quit_running_app
  if [ -x /Library/PrivilegedHelperTools/com.fluxbar.powerd ]; then
    info "Removing the battery helper (asks for your password)"
    sudo /Library/PrivilegedHelperTools/com.fluxbar.powerd uninstall || warn "Could not remove the battery helper."
  fi
  APP="$(find_installed_app || true)"
  [ -n "$APP" ] && { info "Removing $APP"; rm -rf "$APP"; }
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" ${BIN_DIR:+"$BIN_DIR"}; do
    for c in flux clip; do
      if [ -L "$d/$c" ] && [[ "$(readlink "$d/$c")" == *FluxBar.app* ]]; then rm -f "$d/$c"; fi
    done
  done
  rm -f "$HOME/Library/LaunchAgents/com.fluxbar.FluxBar.plist"
  if [ "$PURGE" = 1 ]; then
    info "Deleting clipboard history and settings"
    rm -rf "$HOME/Library/Application Support/FluxBar" "$HOME/Library/Application Support/ClipSuite"
    security delete-generic-password -s com.notchkit.clipcore >/dev/null 2>&1 || true
  fi
  bold "FluxBar removed."
  exit 0
fi

# ------------------------------------------------------------------ download
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${FLUXBAR_ZIP:-}" ]; then
  cp "$FLUXBAR_ZIP" "$TMP/FluxBar.zip"
else
  if [ "$VERSION" = "latest" ]; then
    BASE="https://github.com/$REPO/releases/latest/download"
  else
    BASE="https://github.com/$REPO/releases/download/v$VERSION"
  fi
  info "Downloading FluxBar ($VERSION)"
  curl -fL --progress-bar "$BASE/FluxBar.zip" -o "$TMP/FluxBar.zip" || die "Download failed. Check https://github.com/$REPO/releases"
  if curl -fsSL "$BASE/FluxBar.zip.sha256" -o "$TMP/FluxBar.zip.sha256" 2>/dev/null; then
    EXPECTED="$(awk '{print $1}' "$TMP/FluxBar.zip.sha256")"
    ACTUAL="$(shasum -a 256 "$TMP/FluxBar.zip" | awk '{print $1}')"
    [ "$EXPECTED" = "$ACTUAL" ] || die "Checksum mismatch, download may be corrupted."
  else
    warn "No checksum published for this release; skipping verification."
  fi
fi

ditto -x -k "$TMP/FluxBar.zip" "$TMP/unpacked" || die "Could not unpack FluxBar.zip"
[ -d "$TMP/unpacked/FluxBar.app" ] || die "FluxBar.app not found in the download."
codesign --verify --strict "$TMP/unpacked/FluxBar.app" 2>/dev/null || die "FluxBar.app signature is invalid."

# ------------------------------------------------------------------ install
pick_app_dir
pick_bin_dir
quit_running_app

APP="$APP_DIR/FluxBar.app"
info "Installing to $APP"
rm -rf "$APP"
ditto "$TMP/unpacked/FluxBar.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

info "Linking commands into $BIN_DIR"
for c in flux clip; do
  ln -sf "$APP/Contents/MacOS/$c" "$BIN_DIR/$c"
done

# Remove copies left by `make install-cli` from older versions.
for d in /usr/local/bin "$HOME/.local/bin"; do
  for c in nkit com.fluxbar.powerd; do
    [ -f "$d/$c" ] && [ ! -L "$d/$c" ] && [ -w "$d" ] && rm -f "$d/$c"
  done
done

# Upgrade an existing battery helper so it matches this version.
if [ -x /Library/PrivilegedHelperTools/com.fluxbar.powerd ] && [ -t 0 -o -e /dev/tty ]; then
  if ! cmp -s "$APP/Contents/MacOS/com.fluxbar.powerd" /Library/PrivilegedHelperTools/com.fluxbar.powerd; then
    info "Updating the battery helper (asks for your password)"
    sudo "$APP/Contents/MacOS/com.fluxbar.powerd" install </dev/tty || warn "Battery helper not updated. Run: flux power install"
  fi
fi

VERSION_INSTALLED="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
[ "$LAUNCH" = 1 ] && open "$APP"

echo
bold "FluxBar $VERSION_INSTALLED installed."
echo "  App:       $APP"
echo "  Commands:  flux, clip  (in $BIN_DIR)"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo
  warn "$BIN_DIR is not in your PATH. Add this to ~/.zshrc:"
  echo "    export PATH=\"$BIN_DIR:\$PATH\""
fi
echo
echo "Next steps:"
echo "  flux power install     # one-time: enable the battery charge limit"
echo "  flux power limit 80    # hold charge at 80%"
echo "  flux clip list         # recent clipboard history"
