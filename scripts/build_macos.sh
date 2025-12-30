#!/usr/bin/env bash
set -e

# Script is inside /scripts, so go up one directory to project root
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
MACOS_RUNNER_DIR="$UI_DIR/macos/Runner"
DIST_DIR="$ROOT_DIR/dist"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)

# Timestamp for release naming
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

echo "Root:        $ROOT_DIR"
echo "Core:        $CORE_DIR"
echo "UI:          $UI_DIR"
echo "Runner:      $MACOS_RUNNER_DIR"
echo "Dist:        $DIST_DIR"
echo "Version:     $VERSION"
echo "Timestamp:   $TIMESTAMP"

echo ""
echo "=== Step 1: Build Rust core ==="
cd "$CORE_DIR"
cargo build --release

echo ""
echo "=== Step 2: Copy liblumen_core.dylib into macOS Runner ==="
mkdir -p "$MACOS_RUNNER_DIR"
cp "$CORE_DIR/target/release/liblumen_core.dylib" "$MACOS_RUNNER_DIR/"

echo ""
echo "=== Step 3: Build Flutter macOS release ==="
cd "$UI_DIR"
flutter build macos --release

echo ""
echo "=== Step 4: Package .app into a zip ==="
mkdir -p "$DIST_DIR"

APP_PATH="$UI_DIR/build/macos/Build/Products/Release/Lumen.app"
ZIP_NAME="Lumen-macos-v${VERSION}-${TIMESTAMP}.zip"

cd "$(dirname "$APP_PATH")"
zip -r "$DIST_DIR/$ZIP_NAME" "$(basename "$APP_PATH")"

echo ""
echo "=== DONE ==="
echo "Created: dist/$ZIP_NAME"
