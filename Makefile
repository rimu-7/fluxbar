# On a normal Mac with Xcode or working Command Line Tools, plain `swift` works and these are ignored.
# This machine's CLT ship a mismatched PackageDescription, so fall back to the patched toolchain if present.
ifneq ($(wildcard /tmp/test_patch/usr/bin/swiftc),)
export SWIFT_EXEC ?= /tmp/test_patch/usr/bin/swiftc
export SWIFT_EXEC_MANIFEST ?= $(PWD)/scripts/swiftc-manifest
endif

.PHONY: all build test run app dmg install uninstall icon clean

all: build

build:
	swift build

test:
	./scripts/run-tests.sh

run: build
	.build/debug/FluxBar

# dist/FluxBar.app + FluxBar.zip + FluxBar.dmg
app:
	./scripts/build-app.sh

dmg: app

# Build and install locally exactly like the curl installer would.
install: app
	FLUXBAR_ZIP=dist/FluxBar.zip ./scripts/install.sh

uninstall:
	./scripts/install.sh --uninstall

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	swift package clean
	rm -rf dist
