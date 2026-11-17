#!/usr/bin/env bash
#
# verify_version_tag <tag>
#
# Verifies that a release tag points at a commit whose version files all
# match the tag name. Catches the class of bug where sync.sh tagged a
# pre-bump commit (tag says v4.0.2 but pubspec still says 4.0.1).
#
# Usage:
#   scripts/verify_version_tag.sh v4.0.3
#
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
    echo "Usage: $0 <tag>" >&2
    exit 1
fi

TAG="${TAG#v}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_PUBSPEC="$ROOT_DIR/ui/pubspec.yaml"
ROOT_CARGO="$ROOT_DIR/Cargo.toml"
CORE_CARGO="$ROOT_DIR/core/Cargo.toml"

# Version recorded in the tag's tree.
PUBSPEC_VERSION=$(git -C "$ROOT_DIR" show "$TAG:ui/pubspec.yaml" \
    | grep '^version:' | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')
ROOT_CARGO_VERSION=$(git -C "$ROOT_DIR" show "$TAG:Cargo.toml" \
    | grep '^version =' | head -1 | sed 's/.*"\(.*\)".*/\1/')
CORE_CARGO_VERSION=$(git -C "$ROOT_DIR" show "$TAG:core/Cargo.toml" \
    | grep '^version =' | head -1 | sed 's/.*"\(.*\)".*/\1/')

fail=0
if [ "$PUBSPEC_VERSION" != "$TAG" ]; then
    echo "FAIL: $TAG -> ui/pubspec.yaml version is '$PUBSPEC_VERSION' (expected '$TAG')" >&2
    fail=1
fi
if [ "$ROOT_CARGO_VERSION" != "$TAG" ]; then
    echo "FAIL: $TAG -> Cargo.toml version is '$ROOT_CARGO_VERSION' (expected '$TAG')" >&2
    fail=1
fi
if [ "$CORE_CARGO_VERSION" != "$TAG" ]; then
    echo "FAIL: $TAG -> core/Cargo.toml version is '$CORE_CARGO_VERSION' (expected '$TAG')" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "Tag $TAG does not match its version files — do not release from it." >&2
    exit 1
fi

echo "Tag $TAG is consistent: $PUBSPEC_VERSION across pubspec + both Cargo.toml files"
exit 0
