#!/usr/bin/env bash
set -e
export GZIP=-n

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

# Extract version from Flutter pubspec.yaml (strip CRLF + newline)
VERSION=$(grep '^version:' "$ROOT_DIR/ui/pubspec.yaml" \
    | awk '{print $2}' \
    | cut -d'+' -f1 \
    | tr -d '\r' \
    | tr -d '\n')

printf 'VERSION raw: "%s"\n' "$VERSION"
printf 'VERSION escaped: %q\n' "$VERSION"

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
echo "=== Step 2: Normalize CRLF in directory names ==="
find "$SRC_DIR" -depth -name '*'$'\r' -exec bash -c '
    for f; do mv "$f" "${f%$'\''\r'\''}"; done
' _ {} +

echo ""
echo "=== Step 3: Normalize CRLF line endings ==="
find "$SRC_DIR" -type f -print0 | xargs -0 dos2unix || true

echo ""
echo "=== Step 4: Create source tarball ==="
mkdir -p "$DIST_DIR"
cd "$ROOT_DIR"

TAR_NAME="Lumen-$VERSION.tar.gz"
tar --format=gnu -czvf "$DIST_DIR/$TAR_NAME" "Lumen-$VERSION"

rm -rf "$SRC_DIR"

echo ""
echo "=== DONE ==="
echo "Created: dist/$TAR_NAME"
