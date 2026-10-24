#!/usr/bin/env bash
#
# Build the Linux release artifacts:
#   - portable tarball
#   - Debian package (.deb)
#   - AppImage
#
# Usage: scripts/build_linux.sh
# Env:
#   APPIMAGETOOL=/path/to/appimagetool   use an existing appimagetool
#   SKIP_APPIMAGE=1                      skip AppImage packaging
#   SKIP_DEB=1                           skip Debian packaging
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"
UI_DIR="$ROOT_DIR/ui"
LINUX_LIB_DIR="$UI_DIR/linux/lib"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$UI_DIR/build/linux/x64/release/bundle"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from ui/pubspec.yaml" >&2
    exit 1
fi

# Map the host CPU to package / AppImage architecture names.
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64)
        DEB_ARCH="amd64"
        APPIMAGE_ARCH="x86_64"
        ;;
    aarch64|arm64)
        DEB_ARCH="arm64"
        APPIMAGE_ARCH="aarch64"
        ;;
    *)
        DEB_ARCH="$HOST_ARCH"
        APPIMAGE_ARCH="$HOST_ARCH"
        ;;
esac

echo "Root:      $ROOT_DIR"
echo "Core:      $CORE_DIR"
echo "UI:        $UI_DIR"
echo "Dist:      $DIST_DIR"
echo "Version:   $VERSION"
echo "Arch:      $DEB_ARCH ($APPIMAGE_ARCH)"

echo ""
echo "=== Step 1: Build Rust Workspace (Core + TUI) ==="
cargo build --release --locked

echo ""
echo "=== Step 2: Stage FFI .so into Flutter lib/ dir ==="
mkdir -p "$LINUX_LIB_DIR"
cp "$ROOT_DIR/target/release/liblumen_core.so" "$LINUX_LIB_DIR/"

echo ""
echo "=== Step 3: Build Flutter Linux release ==="
cd "$UI_DIR"
flutter config --enable-linux-desktop
flutter build linux --release
cd "$ROOT_DIR"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "ERROR: Flutter bundle not found at $BUNDLE_DIR" >&2
    exit 1
fi

echo ""
echo "=== Step 4: Add the Rust TUI to the bundle ==="
cp "$ROOT_DIR/target/release/lumen" "$BUNDLE_DIR/lumen-cli"
chmod +x "$BUNDLE_DIR/lumen-cli"

mkdir -p "$DIST_DIR"

echo ""
echo "=== Step 5: Portable tarball ==="
TAR_NAME="Lumen-linux-v${VERSION}.tar.gz"
cd "$BUNDLE_DIR/.."
tar czf "$DIST_DIR/$TAR_NAME" bundle
cd "$ROOT_DIR"
echo "Created: $DIST_DIR/$TAR_NAME"

# ---------------------------------------------------------------------------
# Debian package
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 6: Debian package (.deb) ==="
if [ "${SKIP_DEB:-0}" = "1" ]; then
    echo "SKIPPED: SKIP_DEB=1"
elif ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "SKIPPED: dpkg-deb not found (install dpkg or build on Debian/Ubuntu)." >&2
else
    DEB_ROOT="$DIST_DIR/deb-root"
    rm -rf "$DEB_ROOT"
    install -d "$DEB_ROOT/DEBIAN" \
               "$DEB_ROOT/opt/lumen" \
               "$DEB_ROOT/usr/bin" \
               "$DEB_ROOT/usr/share/applications" \
               "$DEB_ROOT/usr/share/icons/hicolor/1024x1024/apps" \
               "$DEB_ROOT/usr/share/doc/lumen"

    cp -a "$BUNDLE_DIR/." "$DEB_ROOT/opt/lumen/"

    # Launch wrappers. The Flutter bundle must stay together in /opt/lumen.
    ln -sf /opt/lumen/lumen "$DEB_ROOT/usr/bin/lumen"
    ln -sf /opt/lumen/lumen-cli "$DEB_ROOT/usr/bin/lumen-cli"

    install -Dm644 "$ROOT_DIR/scripts/lumen.desktop" \
        "$DEB_ROOT/usr/share/applications/lumen.desktop"
    install -Dm644 "$UI_DIR/lib/assets/lumen_logo.png" \
        "$DEB_ROOT/usr/share/icons/hicolor/1024x1024/apps/lumen.png"
    install -Dm644 "$ROOT_DIR/LICENSE" "$DEB_ROOT/usr/share/doc/lumen/copyright"

    cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: lumen
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Crazygiscool <crazygiscool@proton.me>
Homepage: https://github.com/Crazygiscool/Lumen
Depends: libc6, libstdc++6, libgtk-3-0 | libgtk-3-0t64, libglib2.0-0 | libglib2.0-0t64, liblzma5, libsecret-1-0
Description: Private, encrypted Markdown journal
 Lumen is an offline-first journal with AES-256-GCM encrypted notes,
 Markdown editing, imports, plugins, and a terminal client.
EOF

    DEB_NAME="Lumen-linux-v${VERSION}-${DEB_ARCH}.deb"
    dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DIST_DIR/$DEB_NAME" >/dev/null
    rm -rf "$DEB_ROOT"
    echo "Created: $DIST_DIR/$DEB_NAME"
fi

# ---------------------------------------------------------------------------
# AppImage
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 7: AppImage ==="
if [ "${SKIP_APPIMAGE:-0}" = "1" ]; then
    echo "SKIPPED: SKIP_APPIMAGE=1"
else
    APPIMAGETOOL="${APPIMAGETOOL:-}"
    if [ -z "$APPIMAGETOOL" ] && command -v appimagetool >/dev/null 2>&1; then
        APPIMAGETOOL="$(command -v appimagetool)"
    fi
    if [ -z "$APPIMAGETOOL" ] && [ -x "$ROOT_DIR/tools/appimagetool" ]; then
        APPIMAGETOOL="$ROOT_DIR/tools/appimagetool"
    fi
    if [ -z "$APPIMAGETOOL" ]; then
        APPIMAGETOOL="$ROOT_DIR/target/appimagetool-${APPIMAGE_ARCH}.AppImage"
        if [ ! -x "$APPIMAGETOOL" ]; then
            echo "Downloading appimagetool for ${APPIMAGE_ARCH}..."
            mkdir -p "$(dirname "$APPIMAGETOOL")"
            curl -fL --retry 3 --retry-delay 2 \
                -o "$APPIMAGETOOL" \
                "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage"
            chmod +x "$APPIMAGETOOL"
        fi
    fi

    APPDIR="$DIST_DIR/Lumen.AppDir"
    rm -rf "$APPDIR"
    install -d "$APPDIR/usr/lib/lumen" \
               "$APPDIR/usr/share/icons/hicolor/1024x1024/apps"

    cp -a "$BUNDLE_DIR/." "$APPDIR/usr/lib/lumen/"

    install -Dm644 "$ROOT_DIR/scripts/lumen.desktop" "$APPDIR/lumen.desktop"
    install -Dm644 "$UI_DIR/lib/assets/lumen_logo.png" "$APPDIR/lumen.png"
    install -Dm644 "$UI_DIR/lib/assets/lumen_logo.png" \
        "$APPDIR/usr/share/icons/hicolor/1024x1024/apps/lumen.png"
    ln -sf lumen.png "$APPDIR/.DirIcon"

    cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
set -e
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE/usr/lib/lumen"
exec ./lumen "$@"
EOF
    chmod +x "$APPDIR/AppRun"

    APPIMAGE_NAME="Lumen-linux-v${VERSION}-${APPIMAGE_ARCH}.AppImage"
    APPIMAGE_OUT="$DIST_DIR/$APPIMAGE_NAME"

    # AppImages downloaded from GitHub need libfuse2 on some runners. Extracting
    # and running avoids that dependency entirely.
    if [[ "$APPIMAGETOOL" == *.AppImage ]]; then
        ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 \
            "$APPIMAGETOOL" --no-appstream "$APPDIR" "$APPIMAGE_OUT"
    else
        ARCH="$APPIMAGE_ARCH" "$APPIMAGETOOL" --no-appstream "$APPDIR" "$APPIMAGE_OUT"
    fi
    chmod +x "$APPIMAGE_OUT"
    rm -rf "$APPDIR"
    echo "Created: $APPIMAGE_OUT"
fi

echo ""
echo "=== DONE ==="
echo "Bundle: $BUNDLE_DIR"
ls -lh "$DIST_DIR"
