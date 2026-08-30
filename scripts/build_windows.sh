#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"
DIST_DIR="$ROOT_DIR/dist"
TARGET="x86_64-pc-windows-msvc"

VERSION=$(grep '^version:' "$UI_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1 | tr -d '\r\n')

echo "=== Lumen Windows Build/Test ==="
echo "Host OS: $(uname)"

echo ""
echo "=== Step 1: Rust Check/Build ==="
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Notice: Running on Linux. Testing Rust code compatibility for Windows."
    # We use 'check' because 'build' requires the MSVC linker
    cargo check --workspace --locked --target x86_64-pc-windows-msvc || echo "Warning: Windows target not installed."
    # Create dummy for script flow
    mkdir -p "target/$TARGET/release"
    touch "target/$TARGET/release/lumen_core.dll"
    touch "target/$TARGET/release/fscore.dll"
    touch "target/$TARGET/release/ublock.dll"
    touch "target/$TARGET/release/lumen.exe"
else
    cargo build --release --locked --target "$TARGET"

    echo ""
    echo "=== Step 2: Stage FFI DLLs into Flutter lib/ dir ==="
    mkdir -p "$UI_DIR/windows/lib"
    cp "$ROOT_DIR/target/$TARGET/release/lumen_core.dll" "$UI_DIR/windows/lib/"
    cp "$ROOT_DIR/target/$TARGET/release/fscore.dll" "$UI_DIR/windows/lib/"
    cp "$ROOT_DIR/target/$TARGET/release/ublock.dll" "$UI_DIR/windows/lib/"
fi

echo ""
echo "=== Step 3: Flutter Build ==="
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Notice: Flutter cannot build Windows apps on Linux. Skipping."
else
    cd "$UI_DIR"
    flutter config --enable-windows-desktop
    flutter build windows --release
    echo ""
    echo "=== Step 4: Packaging ==="
    mkdir -p "$DIST_DIR"
    BUNDLE_DIR="$UI_DIR/build/windows/x64/runner/Release"
    ZIP_NAME="Lumen-windows-v${VERSION}.zip"

    # Bundle TUI
    cp "$ROOT_DIR/target/$TARGET/release/lumen.exe" "$BUNDLE_DIR/lumen-cli.exe"

    # Convert paths for Windows-native tools (PowerShell / ISCC). Git Bash
    # produces POSIX paths; cygpath converts them to Windows form when present.
    WIN_BUNDLE_DIR="$BUNDLE_DIR"
    WIN_ROOT_DIR="$ROOT_DIR"
    if command -v cygpath >/dev/null 2>&1; then
        WIN_BUNDLE_DIR="$(cygpath -w "$BUNDLE_DIR")"
        WIN_ROOT_DIR="$(cygpath -w "$ROOT_DIR")"
    fi

    cd "$BUNDLE_DIR"
    if command -v zip >/dev/null 2>&1; then
        zip -r "$DIST_DIR/$ZIP_NAME" .
    else
        WIN_DIST_DIR="$DIST_DIR"
        if command -v cygpath >/dev/null 2>&1; then
            WIN_DIST_DIR="$(cygpath -w "$DIST_DIR")"
        fi
        powershell -NoProfile -Command "Compress-Archive -Path \"$WIN_BUNDLE_DIR\\*\" -DestinationPath \"$WIN_DIST_DIR\\$ZIP_NAME\" -Force"
    fi

    echo ""
    echo "=== Step 5: Build Inno Setup installer ==="
    if command -v iscc >/dev/null 2>&1; then
        ISCC="$(command -v iscc)"
    elif [ -f "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" ]; then
        ISCC="$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe"
    elif [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
        ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
    else
        ISCC=""
    fi

    if [ -n "$ISCC" ]; then
        "$ISCC" /DAPP_VERSION="$VERSION" /DBUNDLE_DIR="$WIN_BUNDLE_DIR" "$WIN_ROOT_DIR/scripts/lumen.iss"
        echo "Installer: $DIST_DIR/Lumen-windows-v${VERSION}-setup.exe"
    else
        echo "SKIPPED: Inno Setup (ISCC) not found. Install with: choco install innosetup -y"
    fi
fi

echo "=== Windows Build Step Finished ==="
