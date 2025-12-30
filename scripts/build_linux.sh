#!/usr/bin/env bash
set -e

# Script is inside /scripts, so go up one directory to project root
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
LINUX_LIB_DIR="$UI_DIR/linux/lib"
OUTPUT_DIR="$UI_DIR/build/linux/x64/release/bundle"
DIST_DIR="$ROOT_DIR/dist"

# Extract version from Flutter pubspec.yaml
VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)

# Generate timestamp
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

echo "Root:        $ROOT_DIR"
echo "Core:        $CORE_DIR"
echo "UI:          $UI_DIR"
echo "Linux lib:   $LINUX_LIB_DIR"
echo "Output:      $OUTPUT_DIR"
echo "Dist:        $DIST_DIR"
echo "Version:     $VERSION"
echo "Timestamp:   $TIMESTAMP"

echo ""
echo "=== Step 1: Build Rust core ==="
cd "$CORE_DIR"
cargo build --release

echo ""
echo "=== Step 2: Copy liblumen_core.so into Flutter linux/lib ==="
mkdir -p "$LINUX_LIB_DIR"
cp "$CORE_DIR/target/release/liblumen_core.so" "$LINUX_LIB_DIR/"

echo ""
echo "=== Step 3: Build Flutter Linux release ==="
cd "$UI_DIR"
flutter build linux --release

echo ""
echo "=== Step 4: Package final tar.gz ==="
mkdir -p "$DIST_DIR"
cd "$OUTPUT_DIR"

TAR_NAME="Lumen-linux-x64-v${VERSION}-${TIMESTAMP}.tar.gz"
tar -czvf "$DIST_DIR/$TAR_NAME" *

echo ""
echo "=== DONE ==="
echo "Created: dist/$TAR_NAME"
