#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
DIST_DIR="$ROOT_DIR/dist"
TARGET="x86_64-pc-windows-msvc"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')

echo "Root:    $ROOT_DIR"
echo "Core:    $CORE_DIR"
echo "UI:      $UI_DIR"
echo "Dist:    $DIST_DIR"
echo "Version: $VERSION"
echo "Target:  $TARGET"

# ── Prerequisite check ──────────────────────────────────────────────
if [ ! -d "$UI_DIR/windows" ]; then
    echo ""
    echo "ERROR: ui/windows/ not found."
    echo "Run this once to generate Windows platform files:"
    echo "  cd ui && flutter create --platforms=windows ."
    echo "  flutter config --enable-windows-desktop"
    exit 1
fi

echo ""
echo "=== Step 1: Build Rust Workspace (Core + TUI) ==="
cargo build --release --locked --target "$TARGET"

echo ""
echo "=== Step 2: Build Flutter Windows release ==="
cd "$UI_DIR"
flutter build windows --release
cd "$ROOT_DIR"

echo ""
echo "=== Step 3: Copy binaries into Flutter bundle ==="
BUNDLE_DIR="$UI_DIR/build/windows/runner/release"
mkdir -p "$UI_DIR/windows/lib"
cp "$ROOT_DIR/target/$TARGET/release/lumen_core.dll" "$UI_DIR/windows/lib/"
cp "$ROOT_DIR/target/$TARGET/release/lumen.exe" "$BUNDLE_DIR/lumen-cli.exe"

echo ""
echo "=== Step 4: Package bundle into zip ==="
mkdir -p "$DIST_DIR"

BUNDLE_DIR="$UI_DIR/build/windows/runner/release"
ZIP_NAME="Lumen-windows-v${VERSION}.zip"
cd "$BUNDLE_DIR"
zip -r "$DIST_DIR/$ZIP_NAME" .

echo ""
echo "=== DONE ==="
echo "Bundle: $BUNDLE_DIR"
echo "Archive: $DIST_DIR/$ZIP_NAME"
