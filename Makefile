# The manifest wrapper passes through on healthy toolchains and works around
# stale SwiftPM private interfaces in some Command Line Tools installs.
export SWIFT_EXEC_MANIFEST ?= $(CURDIR)/scripts/swiftc-manifest

# Honor an explicit SDKROOT; otherwise avoid incomplete CLT SwiftUI SDKs.
ifeq ($(origin SDKROOT), undefined)
export SDKROOT := $(shell bash ./scripts/select-sdk.sh)
endif

# Keep support for the optional local compiler used by older setups.
ifneq ($(wildcard /tmp/test_patch/usr/bin/swiftc),)
export SWIFT_EXEC ?= /tmp/test_patch/usr/bin/swiftc
endif

.PHONY: all build test run preview app dmg install uninstall icon clean

all: build

build:
	swift build

test:
	./scripts/run-tests.sh

run: build
	.build/debug/FluxBar

preview: build
	.build/debug/FluxBar --preview

# dist/FluxBar.app + FluxBar.zip + FluxBar.dmg
app:
	./scripts/build-app.sh

dmg: app

# Open the built DMG for the same Finder installation used by end users.
install: app
	open dist/FluxBar.dmg

uninstall:
	./scripts/install.sh --uninstall

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	swift package clean
	rm -rf dist
