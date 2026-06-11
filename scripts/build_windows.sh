#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"
DIST_DIR="$ROOT_DIR/dist"
TARGET="x86_64-pc-windows-msvc"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')

echo "=== Lumen Windows Build/Test ==="
echo "Host OS: $(uname)"

echo ""
echo "=== Step 1: Rust Check/Build ==="
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Notice: Running on Linux. Testing Rust code compatibility for Windows."
    # We use 'check' because 'build' requires the MSVC linker
    cargo check --workspace --target x86_64-pc-windows-msvc || echo "Warning: Windows target not installed."
    # Create dummy for script flow
    mkdir -p "target/$TARGET/release"
    touch "target/$TARGET/release/lumen_core.dll"
    touch "target/$TARGET/release/lumen.exe"
else
    cargo build --release --locked --target "$TARGET"
fi

echo ""
echo "=== Step 2: Flutter Build ==="
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Notice: Flutter cannot build Windows apps on Linux. Skipping."
else
    cd "$UI_DIR"
    flutter config --enable-windows-desktop
    flutter build windows --release

    echo ""
    echo "=== Step 3: Packaging ==="
    mkdir -p "$DIST_DIR"
    BUNDLE_DIR="$UI_DIR/build/windows/runner/release"
    ZIP_NAME="Lumen-windows-v${VERSION}.zip"

    # Bundle TUI
    cp "$ROOT_DIR/target/$TARGET/release/lumen.exe" "$BUNDLE_DIR/lumen-cli.exe"

    cd "$BUNDLE_DIR"
    zip -r "$DIST_DIR/$ZIP_NAME" .
fi

echo "=== Windows Build Step Finished ==="
