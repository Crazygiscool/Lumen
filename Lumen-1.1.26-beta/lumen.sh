#!/usr/bin/env bash
set -e

# -----------------------------------------
# CONFIG
# -----------------------------------------
CORE_DIR="core"
UI_DIR="ui"
LIB_NAME="liblumen_core.so"
TARGET_LIB="$CORE_DIR/target/release/$LIB_NAME"

# Flutter bundle output directory
FLUTTER_BUNDLE_DIR="$UI_DIR/build/linux/x64/debug/bundle"

# -----------------------------------------
# STEP 0 — Parse arguments
# -----------------------------------------
DEV_MODE=false
TUI_MODE=false

for arg in "$@"; do
    case $arg in
        --dev)
            DEV_MODE=true
            ;;
        --tui)
            TUI_MODE=true
            ;;
    esac
done

# -----------------------------------------
# STEP 1 — Build Rust backend
# -----------------------------------------
echo "🔨 Building Rust backend..."
cd "$CORE_DIR"
cargo build --release
cd ..

# -----------------------------------------
# DEV MODE: Run flutter run (DDS + hot reload)
# -----------------------------------------
if [ "$DEV_MODE" = true ]; then
    echo "🧪 Dev mode enabled — running with flutter run (DDS + hot reload)"
    cd "$UI_DIR"
    flutter run
    cd ..

    if [ "$TUI_MODE" = true ]; then
        echo "🖥️ Running Rust TUI..."
        cargo run --manifest-path "$CORE_DIR/Cargo.toml" --bin lumen_tui
    fi

    echo "✨ Dev session ended."
    exit 0
fi

# -----------------------------------------
# STEP 2 — Build Flutter bundle (normal mode)
# -----------------------------------------
echo "📦 Building Flutter bundle..."
cd "$UI_DIR"
flutter build linux --debug
cd ..

mkdir -p "$FLUTTER_BUNDLE_DIR"
mkdir -p "$FLUTTER_BUNDLE_DIR/lib"   # <-- THIS WAS MISSING

# -----------------------------------------
# STEP 3 — Copy .so into Flutter bundle
# -----------------------------------------
if [ ! -f "$TARGET_LIB" ]; then
    echo "❌ ERROR: $TARGET_LIB does not exist."
    echo "Make sure your Cargo.toml has:"
    echo "[lib]"
    echo "crate-type = [\"cdylib\"]"
    exit 1
fi

echo "🔗 Copying shared library into Flutter bundle..."
cp "$TARGET_LIB" "$FLUTTER_BUNDLE_DIR/lib/$LIB_NAME"
echo "✔ Linked: $FLUTTER_BUNDLE_DIR/lib/$LIB_NAME"

# -----------------------------------------
# STEP 4 — Run Flutter frontend (compiled binary)
# -----------------------------------------
echo "🚀 Running Lumen from bundle..."
"$FLUTTER_BUNDLE_DIR"/Lumen

# -----------------------------------------
# STEP 5 — Optional: Run Rust TUI backend AFTER UI closes
# -----------------------------------------
if [ "$TUI_MODE" = true ]; then
    echo "🖥️ Running Rust TUI..."
    cargo run --manifest-path "$CORE_DIR/Cargo.toml" --bin lumen_tui
fi

echo "✨ Done."
