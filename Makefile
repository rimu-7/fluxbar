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
	cp .build/debug/com.notchkit.powerd /usr/local/bin/com.notchkit.powerd 2>/dev/null || true
	@echo "✅ Installed 'nkit' and 'clip' CLI utilities successfully."

install-helper: build
	@echo "Installing NotchKit privileged power daemon (com.notchkit.powerd)..."
	sudo mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
	sudo cp -f .build/debug/com.notchkit.powerd /Library/PrivilegedHelperTools/com.notchkit.powerd
	sudo chown root:wheel /Library/PrivilegedHelperTools/com.notchkit.powerd
	sudo chmod 755 /Library/PrivilegedHelperTools/com.notchkit.powerd
	sudo cp -f /Library/PrivilegedHelperTools/com.notchkit.powerd /usr/local/bin/notchkit-power-helper
	@echo "✅ Installed and authorized com.notchkit.powerd successfully!"

clean:
	swift package clean
