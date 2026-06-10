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
cargo build --release --locked

echo ""
echo "=== Step 2: Copy liblumen_core.dylib into macOS Runner ==="
mkdir -p "$MACOS_RUNNER_DIR"
cp "$CORE_DIR/target/release/liblumen_core.dylib" "$MACOS_RUNNER_DIR/"

echo ""
echo "=== Step 3: Build Lumen TUI ==="
TUI_DIR="$ROOT_DIR/tui"
cd "$TUI_DIR"
cargo build --release --locked

echo ""
echo "=== Step 4: Build Flutter macOS release ==="
cd "$UI_DIR"
flutter build macos --release

echo ""
echo "=== Step 5: Package .app into a zip ==="
mkdir -p "$DIST_DIR"

APP_PATH="$UI_DIR/build/macos/Build/Products/Release/Lumen.app"
ZIP_NAME="Lumen-macos-v${VERSION}.zip"

# Copy TUI into the release folder before zipping
cp "$TUI_DIR/target/release/lumen" "$DIST_DIR/lumen-cli"

cd "$(dirname "$APP_PATH")"
zip -r "$DIST_DIR/$ZIP_NAME" "$(basename "$APP_PATH")"
# Also add CLI to the zip (we have to move it to the right place first)
cp "$TUI_DIR/target/release/lumen" "$(dirname "$APP_PATH")/lumen-cli"
zip -g "$DIST_DIR/$ZIP_NAME" "lumen-cli"
rm "$(dirname "$APP_PATH")/lumen-cli"

echo ""
echo "=== DONE ==="
echo "Created: dist/$ZIP_NAME"
