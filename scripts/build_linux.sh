#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

# Extract version from Flutter pubspec.yaml
VERSION=$(grep '^version:' "$ROOT_DIR/ui/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)

echo "Root:    $ROOT_DIR"
echo "Dist:    $DIST_DIR"
echo "Version: $VERSION"

echo ""
echo "=== Step 1: Prepare source staging directory ==="
SRC_DIR="$ROOT_DIR/Lumen-$VERSION"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

echo "Copying source tree..."
rsync -av --exclude 'dist' \
          --exclude 'package' \
          --exclude 'target' \
          --exclude 'build' \
          --exclude '.git' \
          --exclude '.dart_tool' \
          --exclude '.idea' \
          --exclude '.vscode' \
          "$ROOT_DIR/" "$SRC_DIR/"

echo ""
echo "=== Step 2: Create source tarball ==="
mkdir -p "$DIST_DIR"
cd "$ROOT_DIR"

TAR_NAME="Lumen-linux-x64-$VERSION.tar.gz"
tar -czvf "$DIST_DIR/$TAR_NAME" "Lumen-$VERSION"

rm -rf "$SRC_DIR"

echo ""
echo "=== DONE ==="
echo "Created: dist/$TAR_NAME"
