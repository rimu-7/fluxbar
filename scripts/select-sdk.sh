#!/usr/bin/env bash
# Select a usable SDK for local Make targets without changing xcode-select.
set -euo pipefail

if [ -n "${SDKROOT:-}" ]; then
  printf '%s\n' "$SDKROOT"
  exit 0
fi

DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
SWIFTC="$(xcrun --find swiftc)"
SWIFT_LIB="$(dirname "$SWIFTC")/../lib/swift"

needs_state_plugin() {
  local sdk="$1"
  local module="$sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule"
  [ -d "$module" ] && grep -q 'type: "StateMacro"' "$module/"*.swiftinterface
}

# Xcode includes the SwiftUI plugins. Only work around CLT installations that
# expose the new @State macro without shipping its implementation.
if [[ "$DEVELOPER_DIR_PATH" != */CommandLineTools ]] ||
   [ -f "$SWIFT_LIB/host/plugins/libSwiftUIMacros.dylib" ] ||
   ! needs_state_plugin "$DEFAULT_SDK"; then
  printf '%s\n' "$DEFAULT_SDK"
  exit 0
fi

SDK_DIR="$(dirname "$DEFAULT_SDK")"
BEST_SDK=""
BEST_MAJOR=0
BEST_MINOR=0
for candidate in "$SDK_DIR"/MacOSX[0-9]*.sdk; do
  [ -d "$candidate" ] || continue
  needs_state_plugin "$candidate" && continue
  version="${candidate##*/MacOSX}"
  version="${version%.sdk}"
  major="${version%%.*}"
  minor=0
  if [[ "$version" == *.* ]]; then
    minor="${version#*.}"
    minor="${minor%%.*}"
  fi
  if ((major > BEST_MAJOR || (major == BEST_MAJOR && minor > BEST_MINOR))); then
    BEST_SDK="$candidate"
    BEST_MAJOR="$major"
    BEST_MINOR="$minor"
  fi
done

# If no alternative is installed, let Swift report the original SDK error.
printf '%s\n' "${BEST_SDK:-$DEFAULT_SDK}"
