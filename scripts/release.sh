#!/usr/bin/env bash
#
# Lumen release script.
#
#   1. Syncs version from ui/pubspec.yaml into the Rust crates and Cargo.lock.
#   2. Commits the bump, tags it vX.Y.Z, and verifies the tag matches.
#   3. Pushes main --follow-tags to GitHub (which starts the release CI).
#
# The release CI (release.yml) builds all platforms, publishes the GitHub
# Release, and updates both AUR packages (lumen-journal source, lumen-journal-bin
# prebuilt). This script no longer touches AUR repos locally.
#
# Usage: scripts/release.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Lumen Release Script ==="
echo ""

# ── Step 1: Bump version, commit, and tag ───────────────────────────
echo "--- Step 1: Syncing versions ---"
"$ROOT_DIR/scripts/sync.sh"

# Read the new version from Cargo.toml (clean semver, no build metadata)
NEW_VERSION=$(grep '^version = ' "$ROOT_DIR/core/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
TAG="v$NEW_VERSION"
echo "New version: $NEW_VERSION (tag: $TAG)"

# ── Step 2: Verify the tag matches its version files ────────────────
echo ""
echo "--- Step 2: Verifying tag ---"
"$ROOT_DIR/scripts/verify_version_tag.sh" "$TAG"

# ── Step 3: Push to GitHub ──────────────────────────────────────────
echo ""
echo "--- Step 3: Push to GitHub ---"
read -rp "Push tag $TAG to GitHub? (y/N) " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git -C "$ROOT_DIR" push --follow-tags
    echo "Pushed to GitHub. Release CI will build and publish."
else
    echo "Skipped. Push manually: git push --follow-tags"
fi

echo ""
echo "=== Release $NEW_VERSION initiated ==="
