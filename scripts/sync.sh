#!/usr/bin/env bash
set -e

# Script is inside /scripts, so go up one directory to project root
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_PUBSPEC="$ROOT_DIR/ui/pubspec.yaml"
CORE_CARGO="$ROOT_DIR/core/Cargo.toml"

DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
    esac
done

echo "Project root: $ROOT_DIR"

# Extract version from pubspec.yaml
RAW_VERSION=$(grep '^version:' "$UI_PUBSPEC" | awk '{print $2}')
BASE_VERSION=$(echo "$RAW_VERSION" | cut -d'+' -f1)

# Split version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"

# Get git commit count
COMMITS=$(git -C "$ROOT_DIR" rev-list --count HEAD)

echo "Current version: $MAJOR.$MINOR.$PATCH"
echo "Git commits: $COMMITS"

# Detect if user manually bumped major/minor
# Strip optional v prefix from last tag for comparison
LAST_TAG=$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "$MAJOR.$MINOR.$PATCH")

IFS='.' read -r LAST_MAJOR LAST_MINOR LAST_PATCH <<< "$LAST_TAG"

if [[ "$MAJOR" == "$LAST_MAJOR" && "$MINOR" == "$LAST_MINOR" ]]; then
    # User did NOT bump major/minor → auto-increment patch
    PATCH=$((PATCH + 1))
    echo "Auto-incrementing patch → $PATCH"
else
    echo "User bumped major/minor → keeping version"
fi

# Build final version string
FINAL_VERSION="$MAJOR.$MINOR.$PATCH+$COMMITS"

echo "Final version: $FINAL_VERSION"

if [ "$DRY_RUN" = true ]; then
    echo "Dry run — no files written."
    exit 0
fi

# Update pubspec.yaml
sed -i.bak "s/^version:.*/version: $FINAL_VERSION/" "$UI_PUBSPEC"
rm "$UI_PUBSPEC.bak"

# Update Cargo.toml
sed -i.bak "s/^version = .*/version = \"$MAJOR.$MINOR.$PATCH\"/" "$CORE_CARGO"
rm "$CORE_CARGO.bak"

echo "Updated:"
echo " - ui/pubspec.yaml"
echo " - core/Cargo.toml"

# Create tag
TAG="v$MAJOR.$MINOR.$PATCH"
if git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists — skipping tag"
else
    git -C "$ROOT_DIR" tag -a "$TAG" -m "Release $MAJOR.$MINOR.$PATCH"
    echo "Created tag: $TAG"
    echo "Push with: git push --follow-tags"
fi

echo "Done."
