# -----------------------------------------------------------------------------
# Lumen — cross-platform Makefile
#
# Replaces lumen.sh / lumen.bat. Works on Linux, macOS and Windows.
# On Windows, GNU Make must be installed and run from a Unix-like shell
# (Git Bash, MSYS2 or WSL).
#
# Targets:
#   make / make run     Build core, link FFI lib, build & run the app
#   make dev            Hot-reload dev mode (DDS + hot reload)
#   make tui            Run the Rust TUI directly
#   make build-linux    Release package: Linux  (delegates to scripts/)
#   make build-macos    Release package: macOS  (delegates to scripts/)
#   make build-windows  Release package: Windows (delegates to scripts/)
#   make help           Show this help
#
# Any target accepts tui=1 to run the Rust TUI afterwards:
#   make tui=1      # build & run app, then the TUI
#   make dev tui=1  # hot reload, then the TUI
# -----------------------------------------------------------------------------

.PHONY: all run dev tui help build-linux build-macos build-windows

# ----- Platform detection ----------------------------------------------------
ifeq ($(OS),Windows_NT)
    PLATFORM       := windows
    LIB_NAME       := lumen_core.dll
    FSCORE_LIB     := fscore.dll
    UBLOCK_LIB     := ublock.dll
    FLUTTER_TARGET := windows
    APP_NAME       := Lumen.exe
    BUNDLE_DIR     := ui/build/windows/x64/debug/bundle
    DEV_LIB_DIR    := ui/windows/lib
    FLUTTER_ENABLE := flutter config --enable-windows-desktop
    LAUNCH          = "$(BUNDLE_DIR)/$(APP_NAME)"
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Darwin)
        PLATFORM       := macos
        LIB_NAME       := liblumen_core.dylib
        FSCORE_LIB     := libfscore.dylib
        UBLOCK_LIB     := libublock.dylib
        FLUTTER_TARGET := macos
        APP_NAME       := Runner.app
        BUNDLE_DIR     := ui/build/macos/Build/Products/Debug
        DEV_LIB_DIR    := ui/macos/Runner
        FLUTTER_ENABLE := flutter config --enable-macos-desktop
        LAUNCH          = open "$(BUNDLE_DIR)/$(APP_NAME)"
    else
        PLATFORM       := linux
        LIB_NAME       := liblumen_core.so
        FSCORE_LIB     := libfscore.so
        UBLOCK_LIB     := libublock.so
        FLUTTER_TARGET := linux
        APP_NAME       := Lumen
        BUNDLE_DIR     := ui/build/linux/x64/debug/bundle
        DEV_LIB_DIR    := ui/linux/lib
        FLUTTER_ENABLE := flutter config --enable-linux-desktop
        LAUNCH          = "$(BUNDLE_DIR)/$(APP_NAME)"
    endif
endif

TARGET_LIB := target/release/$(LIB_NAME)
FSCORE_TARGET := target/release/$(FSCORE_LIB)
UBLOCK_TARGET := target/release/$(UBLOCK_LIB)

# ----- Rules -----------------------------------------------------------------

all: run

## Build core, link the FFI library, build & run the app
run:
	@echo "[Lumen] 🔨 Building Rust backend ($(PLATFORM))..."
	cargo build --release --locked
	@test -f "$(TARGET_LIB)" || { echo "❌ ERROR: $(TARGET_LIB) does not exist."; echo "   Make sure core/Cargo.toml has:"; echo "   [lib]"; echo "   crate-type = [\"cdylib\"]"; exit 1; }
	@echo "[Lumen] 🔗 Linking shared libraries..."
	mkdir -p "$(DEV_LIB_DIR)"
	cp "$(TARGET_LIB)" "$(DEV_LIB_DIR)/$(LIB_NAME)"
	cp "$(FSCORE_TARGET)" "$(DEV_LIB_DIR)/$(FSCORE_LIB)"
	cp "$(UBLOCK_TARGET)" "$(DEV_LIB_DIR)/$(UBLOCK_LIB)"
	@echo "[Lumen] 📦 Building Flutter bundle..."
	cd ui && $(FLUTTER_ENABLE) && flutter build $(FLUTTER_TARGET) --debug
	@mkdir -p "$(BUNDLE_DIR)/lib"
	cp "$(TARGET_LIB)" "$(BUNDLE_DIR)/lib/$(LIB_NAME)"
	cp "$(FSCORE_TARGET)" "$(BUNDLE_DIR)/lib/$(FSCORE_LIB)"
	cp "$(UBLOCK_TARGET)" "$(BUNDLE_DIR)/lib/$(UBLOCK_LIB)"
	@echo "[Lumen] 🚀 Running $(APP_NAME)..."
	$(LAUNCH)
	@if [ "$(tui)" = "1" ]; then echo "[Lumen] 🖥️  Running Rust TUI..."; cargo run --bin lumen; fi
	@echo "[Lumen] ✨ Done."

## Hot-reload dev mode (DDS + hot reload)
dev:
	@echo "[Lumen] 🔨 Building Rust backend ($(PLATFORM))..."
	cargo build --release --locked
	@echo "[Lumen] 🔗 Linking shared libraries..."
	mkdir -p "$(DEV_LIB_DIR)"
	cp "$(TARGET_LIB)" "$(DEV_LIB_DIR)/$(LIB_NAME)"
	cp "$(FSCORE_TARGET)" "$(DEV_LIB_DIR)/$(FSCORE_LIB)"
	cp "$(UBLOCK_TARGET)" "$(DEV_LIB_DIR)/$(UBLOCK_LIB)"
	@echo "[Lumen] 🧪 Dev mode — running flutter run..."
	cd ui && $(FLUTTER_ENABLE) && flutter run
	@if [ "$(tui)" = "1" ]; then echo "[Lumen] 🖥️  Running Rust TUI..."; cargo run --bin lumen; fi
	@echo "[Lumen] ✨ Done."

## Run the Rust TUI directly
tui:
	cargo run --bin lumen

## Release package: Linux
build-linux:
	./scripts/build_linux.sh

## Release package: macOS
build-macos:
	./scripts/build_macos.sh

## Release package: Windows
build-windows:
	./scripts/build_windows.sh

## Show this help
help:
	@echo "Lumen targets:"
	@echo "  make            Build core, link FFI lib, build & run the app"
	@echo "  make dev        Hot-reload dev mode (DDS + hot reload)"
	@echo "  make tui        Run the Rust TUI directly"
	@echo "  make build-linux    Release package: Linux"
	@echo "  make build-macos    Release package: macOS"
	@echo "  make build-windows  Release package: Windows"
	@echo ""
	@echo "Add tui=1 to run the TUI afterwards:  make dev tui=1"