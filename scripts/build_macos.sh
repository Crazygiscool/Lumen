#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
MACOS_RUNNER_DIR="$UI_DIR/macos/Runner"
DIST_DIR="$ROOT_DIR/dist"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')

echo "=== Lumen macOS Build/Test ==="
echo "Host OS: $(uname)"

echo ""
echo "=== Step 1: Rust Check/Build ==="
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Notice: Not on macOS. Running 'cargo check --locked' as a smoke test."
    cargo check --workspace --locked
    # Create a dummy file so Step 2 doesn't fail during local test
    mkdir -p target/release
    touch target/release/liblumen_core.dylib
else
    cargo build --release --locked
fi

echo ""
echo "=== Step 2: Prepare Assets ==="
mkdir -p "$MACOS_RUNNER_DIR"
if [ -f "$ROOT_DIR/target/release/liblumen_core.dylib" ]; then
    cp "$ROOT_DIR/target/release/liblumen_core.dylib" "$MACOS_RUNNER_DIR/"
fi

echo ""
echo "=== Step 3: Flutter Build ==="
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Notice: Flutter cannot build macOS apps on $(uname). Skipping."
else
    cd "$UI_DIR"
    flutter config --enable-macos-desktop
    flutter build macos --release

    echo ""
    echo "=== Step 4: Packaging ==="
    mkdir -p "$DIST_DIR"
    APP_PATH="$UI_DIR/build/macos/Build/Products/Release/Lumen.app"
    ZIP_NAME="Lumen-macos-v${VERSION}.zip"
    TUI_BIN="$ROOT_DIR/target/release/lumen"

    cd "$(dirname "$APP_PATH")"
    zip -r "$DIST_DIR/$ZIP_NAME" "$(basename "$APP_PATH")"
    cp "$TUI_BIN" "lumen-cli"
    zip -g "$DIST_DIR/$ZIP_NAME" "lumen-cli"
    rm "lumen-cli"
fi

echo "=== macOS Build Step Finished ==="
