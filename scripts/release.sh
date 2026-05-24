#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUR_DIR="$ROOT_DIR/lumen-journal"

echo "=== Lumen Release Script ==="
echo ""

# ── Step 1: Bump version and tag ──────────────────────────────────
echo "--- Step 1: Syncing versions ---"
"$ROOT_DIR/scripts/sync.sh"

# Read the new version from Cargo.toml (clean semver, no build metadata)
NEW_VERSION=$(grep '^version = ' "$ROOT_DIR/core/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
TAG="v$NEW_VERSION"
echo "New version: $NEW_VERSION (tag: $TAG)"

# ── Step 2: Push to GitHub ────────────────────────────────────────
echo ""
echo "--- Step 2: Push to GitHub ---"
read -rp "Push tag $TAG to GitHub? (y/N) " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git -C "$ROOT_DIR" push --follow-tags
    echo "Pushed to GitHub."
else
    echo "Skipped. Push manually: git push --follow-tags"
fi

# ── Step 3: Update AUR PKGBUILD ───────────────────────────────────
echo ""
echo "--- Step 3: Updating AUR package ---"
if [ ! -d "$AUR_DIR/.git" ]; then
    echo "AUR repo not found at $AUR_DIR"
    echo "Clone it first: git clone https://aur.archlinux.org/lumen-journal.git \"$AUR_DIR\""
    exit 1
fi

sed -i "s/pkgver=.*/pkgver=$NEW_VERSION/" "$AUR_DIR/PKGBUILD"
echo "Updated pkgver to $NEW_VERSION in PKGBUILD"

cd "$AUR_DIR"
makepkg --printsrcinfo > .SRCINFO
echo "Updated .SRCINFO"

git add -A
git commit -m "bump to $NEW_VERSION"

# ── Step 4: Push to AUR ───────────────────────────────────────────
echo ""
echo "--- Step 4: Push to AUR ---"
read -rp "Push to AUR? (y/N) " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git push origin master
    echo "Pushed to AUR."
else
    echo "Skipped. Push manually from $AUR_DIR: git push origin master"
fi

echo ""
echo "=== Release $NEW_VERSION complete ==="
