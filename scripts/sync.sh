#!/usr/bin/env bash
set -e

# Script is inside /scripts, so go up one directory to project root
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_PUBSPEC="$ROOT_DIR/ui/pubspec.yaml"
ROOT_CARGO="$ROOT_DIR/Cargo.toml"
CORE_CARGO="$ROOT_DIR/core/Cargo.toml"
TUI_CARGO="$ROOT_DIR/tui/Cargo.toml"

DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
    esac
done

echo "Project root: $ROOT_DIR"

# pubspec.yaml is the single source of truth for the product version
# (also used by the release build scripts for artifact filenames).
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
RUST_VERSION="$MAJOR.$MINOR.$PATCH"

echo "Final pubspec version: $FINAL_VERSION"
echo "Synced Rust version:   $RUST_VERSION"

if [ "$DRY_RUN" = true ]; then
    echo "Dry run — no files written."
    exit 0
fi

# Update pubspec.yaml (keeps the +<commits> build metadata)
sed -i.bak "s/^version:.*/version: $FINAL_VERSION/" "$UI_PUBSPEC"
rm "$UI_PUBSPEC.bak"

# Update the Rust workspace package + member package versions.
# fscore/ublock keep their own internal 0.1.0 (helper libs, not the product).
sed -i.bak "s/^version = .*/version = \"$RUST_VERSION\"/" "$ROOT_CARGO"
rm "$ROOT_CARGO.bak"
sed -i.bak "s/^version = .*/version = \"$RUST_VERSION\"/" "$CORE_CARGO"
rm "$CORE_CARGO.bak"
sed -i.bak "s/^version = .*/version = \"$RUST_VERSION\"/" "$TUI_CARGO"
rm "$TUI_CARGO.bak"

# Back to project root so cargo picks up the workspace it belongs to
cd "$ROOT_DIR"
cargo check --workspace --locked >/dev/null 2>&1 || {
    echo "Updating Cargo.lock for new version…"
    cargo check --workspace >/dev/null 2>&1
}

echo "Updated:"
echo " - ui/pubspec.yaml  (version: $FINAL_VERSION)"
echo " - Cargo.toml       (workspace package: $RUST_VERSION)"
echo " - core/Cargo.toml  ($RUST_VERSION)"
echo " - tui/Cargo.toml   ($RUST_VERSION)"

# Create tag
TAG="v$RUST_VERSION"
if git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists — skipping tag"
else
    git -C "$ROOT_DIR" tag -a "$TAG" -m "Release $RUST_VERSION"
    echo "Created tag: $TAG"
    echo "Push with: git push --follow-tags"
fi

echo "Done."
