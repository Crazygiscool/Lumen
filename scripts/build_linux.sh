#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
LINUX_LIB_DIR="$UI_DIR/linux/lib"
DIST_DIR="$ROOT_DIR/dist"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')

echo "Root:    $ROOT_DIR"
echo "Core:    $CORE_DIR"
echo "UI:      $UI_DIR"
echo "Dist:    $DIST_DIR"
echo "Version: $VERSION"

echo ""
echo "=== Step 1: Build Rust Workspace (Core + TUI) ==="
cargo build --release --locked

echo ""
echo "=== Step 2: Stage FFI .so into Flutter lib/ dir ==="
mkdir -p "$LINUX_LIB_DIR"
cp "$ROOT_DIR/target/release/liblumen_core.so" "$LINUX_LIB_DIR/"
cp "$ROOT_DIR/target/release/libfscore.so" "$LINUX_LIB_DIR/"
cp "$ROOT_DIR/target/release/libublock.so" "$LINUX_LIB_DIR/"

echo ""
echo "=== Step 3: Build Flutter Linux release ==="
cd "$UI_DIR"
flutter config --enable-linux-desktop
flutter build linux --release
cd "$ROOT_DIR"

echo ""
echo "=== Step 4: Package bundle into tarball ==="
BUNDLE_DIR="$UI_DIR/build/linux/x64/release/bundle"
mkdir -p "$DIST_DIR"

cp "$ROOT_DIR/target/release/lumen" "$BUNDLE_DIR/lumen-cli"

TAR_NAME="Lumen-linux-v${VERSION}.tar.gz"
cd "$BUNDLE_DIR/.."
tar czf "$DIST_DIR/$TAR_NAME" bundle

echo ""
echo "=== DONE ==="
echo "Bundle: $BUNDLE_DIR"
echo "Archive: $DIST_DIR/$TAR_NAME"
