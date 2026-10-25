#!/usr/bin/env bash
#
# Update the AUR package (lumen-journal) to a released version.
#
# Usage:
#   scripts/update_aur.sh [version]
#
# With no argument the version is read from ui/pubspec.yaml.
#
# Env:
#   AUR_SSH_PRIVATE_KEY  private SSH key for aur@aur.archlinux.org (CI)
#   AUR_KNOWN_HOSTS      optional pinned known_hosts content (CI)
#   AUR_REPO             override the AUR repository URL
#   AUR_DRY_RUN=1        clone/update the package but do not commit or push
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUR_REPO="${AUR_REPO:-ssh://aur@aur.archlinux.org/lumen-journal.git}"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(grep '^version:' "$ROOT_DIR/ui/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')
fi
VERSION="${VERSION#v}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "ERROR: invalid version '$VERSION'" >&2
    exit 1
fi

echo "Updating AUR package lumen-journal to v$VERSION"

WORK_DIR="$(mktemp -d)"
SSH_DIR=""
cleanup() {
    rm -rf "$WORK_DIR"
    if [ -n "$SSH_DIR" ]; then rm -rf "$SSH_DIR"; fi
}
trap cleanup EXIT

# Configure a temporary SSH identity for CI. Locally, the normal ~/.ssh config
# (for example an `aur` Host alias) is used when no secret is supplied.
if [ -n "${AUR_SSH_PRIVATE_KEY:-}" ]; then
    SSH_DIR="$(mktemp -d)"
    chmod 700 "$SSH_DIR"
    printf '%s\n' "$AUR_SSH_PRIVATE_KEY" > "$SSH_DIR/aur_key"
    chmod 600 "$SSH_DIR/aur_key"

    if [ -n "${AUR_KNOWN_HOSTS:-}" ]; then
        printf '%s\n' "$AUR_KNOWN_HOSTS" > "$SSH_DIR/known_hosts"
    else
        ssh-keyscan -t ed25519 aur.archlinux.org > "$SSH_DIR/known_hosts" 2>/dev/null
    fi

    export GIT_SSH_COMMAND="ssh -i $SSH_DIR/aur_key -o IdentitiesOnly=yes -o UserKnownHostsFile=$SSH_DIR/known_hosts -o StrictHostKeyChecking=yes"
fi

git clone --depth=1 "$AUR_REPO" "$WORK_DIR/lumen-journal"
cd "$WORK_DIR/lumen-journal"

if [ ! -f PKGBUILD ] || [ ! -f .SRCINFO ]; then
    echo "ERROR: AUR checkout is missing PKGBUILD or .SRCINFO" >&2
    exit 1
fi

# pkgver drives the source tag in this PKGBUILD, so only the version changes.
sed -i "s/^pkgver=.*/pkgver=$VERSION/" PKGBUILD

if command -v makepkg >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    # Regenerate from PKGBUILD when we are on a real Arch system.
    makepkg --printsrcinfo > .SRCINFO
else
    # Portable fallback for CI runners without makepkg. Only the version and
    # expanded source tag change for a normal release.
    sed -i "s/^\tpkgver = .*/\tpkgver = $VERSION/" .SRCINFO
    sed -i "s|#tag=v[0-9][^[:space:]]*|#tag=v$VERSION|" .SRCINFO
fi

if git diff --quiet; then
    echo "AUR package is already at v$VERSION; nothing to push."
    exit 0
fi

echo ""
git diff -- PKGBUILD .SRCINFO

if [ "${AUR_DRY_RUN:-0}" = "1" ]; then
    echo ""
    echo "AUR_DRY_RUN=1: not committing or pushing."
    exit 0
fi

git config user.name "Lumen Release Bot"
git config user.email "crazygiscool@proton.me"
git add PKGBUILD .SRCINFO
git commit -m "Update to v$VERSION"
git push origin master

echo "AUR updated: https://aur.archlinux.org/packages/lumen-journal"
