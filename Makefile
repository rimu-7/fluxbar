export SWIFT_EXEC ?= /tmp/test_patch/usr/bin/swiftc
export SWIFT_EXEC_MANIFEST ?= $(PWD)/scripts/swiftc-manifest

.PHONY: all build test run run-bar install-cli clean

all: build

build:
	swift build

test:
	./scripts/run-tests.sh

run: build
	.build/debug/NotchKit

run-bar: run

install-cli: build
	mkdir -p /usr/local/bin 2>/dev/null || true
	cp .build/debug/nkit /usr/local/bin/nkit 2>/dev/null || cp .build/debug/nkit $(HOME)/.local/bin/nkit
	cp .build/debug/clip /usr/local/bin/clip 2>/dev/null || cp .build/debug/clip $(HOME)/.local/bin/clip
	@echo "✅ Installed 'nkit' and 'clip' CLI utilities successfully."

install-helper:
	@if [ -f /Library/PrivilegedHelperTools/wattbitd ]; then \
		echo "Authorizing wattbitd helper for hardware charge limiting..."; \
		sudo chmod 4755 /Library/PrivilegedHelperTools/wattbitd && echo "✅ Authorized successfully!" || echo "❌ Authorization cancelled."; \
	fi

clean:
	swift package clean
