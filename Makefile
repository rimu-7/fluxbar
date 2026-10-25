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
	cp .build/debug/clip /usr/local/bin/clip || cp .build/debug/clip $(HOME)/.local/bin/clip
	@echo "Installed clip CLI successfully."

clean:
	swift package clean
