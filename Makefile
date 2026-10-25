export SWIFT_EXEC ?= /tmp/test_patch/usr/bin/swiftc
export SWIFT_EXEC_MANIFEST ?= $(PWD)/scripts/swiftc-manifest

.PHONY: all build test run run-bar install-cli clean

all: build

build:
	swift build

test:
	./scripts/run-tests.sh

run: build
	.build/debug/FluxBar

run-bar: run

install-cli: build
	mkdir -p /usr/local/bin 2>/dev/null || true
	cp .build/debug/flux /usr/local/bin/flux 2>/dev/null || cp .build/debug/flux $(HOME)/.local/bin/flux
	cp .build/debug/nkit /usr/local/bin/nkit 2>/dev/null || cp .build/debug/nkit $(HOME)/.local/bin/nkit
	cp .build/debug/clip /usr/local/bin/clip 2>/dev/null || cp .build/debug/clip $(HOME)/.local/bin/clip
	cp .build/debug/com.fluxbar.powerd /usr/local/bin/com.fluxbar.powerd 2>/dev/null || true
	@echo "✅ Installed 'flux', 'nkit', and 'clip' CLI utilities successfully."

install-helper: build
	@echo "Installing FluxBar privileged power daemon (com.fluxbar.powerd)..."
	sudo mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
	sudo cp -f .build/debug/com.fluxbar.powerd /Library/PrivilegedHelperTools/com.fluxbar.powerd
	sudo chown root:wheel /Library/PrivilegedHelperTools/com.fluxbar.powerd
	sudo chmod 755 /Library/PrivilegedHelperTools/com.fluxbar.powerd
	sudo cp -f /Library/PrivilegedHelperTools/com.fluxbar.powerd /usr/local/bin/fluxbar-power-helper
	@echo "✅ Installed and authorized com.fluxbar.powerd successfully!"

clean:
	swift package clean
