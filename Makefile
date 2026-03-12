BINARY_NAME  := dexbar
INSTALL_DIR  ?= $(HOME)/.local/bin
BUILD_DIR    := .build

.PHONY: build run install uninstall clean help

## build: Compile DexBarLinux in debug mode
build:
	swift build --product DexBarLinux

## release: Compile DexBarLinux in release mode
release:
	swift build --product DexBarLinux -c release

## run: Build (debug) and run immediately
run: build
	$(BUILD_DIR)/debug/DexBarLinux

## install: Build release and install to $(INSTALL_DIR)  [override with INSTALL_DIR=/usr/local/bin]
install: release
	@mkdir -p $(INSTALL_DIR)
	cp $(BUILD_DIR)/release/DexBarLinux $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"

## uninstall: Remove installed binary from $(INSTALL_DIR)
uninstall:
	rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Removed $(INSTALL_DIR)/$(BINARY_NAME)"

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## help: Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
