#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <new_version>"
    exit 1
fi

NEW_VER=$1

# 1. Update Cargo.toml (Workspace and members)
# Using a more specific regex to avoid matching dependencies
sed -i "0,/^version = \".*\"/s//version = \"$NEW_VER\"/" Cargo.toml
sed -i "0,/^version = \".*\"/s//version = \"$NEW_VER\"/" core/Cargo.toml
sed -i "0,/^version = \".*\"/s//version = \"$NEW_VER\"/" tui/Cargo.toml

# 2. Update Flutter pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VER/" ui/pubspec.yaml

# 3. Update AUR PKGBUILD
sed -i "s/^pkgver=.*/pkgver=$NEW_VER/" lumen-journal/PKGBUILD
sed -i "s/tag=v[0-9.]*/tag=v$NEW_VER/" lumen-journal/PKGBUILD

# 4. Regenerate .SRCINFO
# Note: This requires 'makepkg' installed on the local system
if command -v makepkg &> /dev/null; then
    cd lumen-journal
    makepkg --printsrcinfo > .SRCINFO
    cd ..
else
    echo "Warning: 'makepkg' not found, .SRCINFO not updated."
fi

# 5. Update Cargo.lock
echo "Updating Cargo.lock..."
cargo update --workspace

echo "Version bumped to $NEW_VER"
