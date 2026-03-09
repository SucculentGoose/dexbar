BINARY_NAME  := dexbar
INSTALL_DIR  := /usr/local/bin
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

## install: Build release and install to $(INSTALL_DIR)
install: release
	@if [ -w $(INSTALL_DIR) ]; then \
		cp $(BUILD_DIR)/release/DexBarLinux $(INSTALL_DIR)/$(BINARY_NAME); \
	else \
		sudo cp $(BUILD_DIR)/release/DexBarLinux $(INSTALL_DIR)/$(BINARY_NAME); \
	fi
	@echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"

## uninstall: Remove installed binary
uninstall:
	@if [ -w $(INSTALL_DIR) ]; then \
		rm -f $(INSTALL_DIR)/$(BINARY_NAME); \
	else \
		sudo rm -f $(INSTALL_DIR)/$(BINARY_NAME); \
	fi
	@echo "Removed $(INSTALL_DIR)/$(BINARY_NAME)"

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## help: Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
