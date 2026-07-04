#!/usr/bin/env bash
set -e

# -----------------------------------------
# CONFIG
# -----------------------------------------
CORE_DIR="core"
UI_DIR="ui"
LIB_NAME="liblumen_core.so"
TARGET_LIB="target/release/$LIB_NAME"

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
# STEP 2 — Ensure shared library is linked
# -----------------------------------------
if [ ! -f "$TARGET_LIB" ]; then
    echo "❌ ERROR: $TARGET_LIB does not exist."
    echo "Make sure your Cargo.toml has:"
    echo "[lib]"
    echo "crate-type = [\"cdylib\"]"
    exit 1
fi

echo "🔗 Linking shared library..."
# Copy to source dir so 'flutter run' and build pick it up
mkdir -p "$UI_DIR/linux/lib"
cp "$TARGET_LIB" "$UI_DIR/linux/lib/$LIB_NAME"
echo "✔ Updated: $UI_DIR/linux/lib/$LIB_NAME"

# -----------------------------------------
# EXECUTION
# -----------------------------------------
if [ "$DEV_MODE" = true ]; then
    echo "🧪 Dev mode enabled — running with flutter run (DDS + hot reload)"
    cd "$UI_DIR"
    flutter run
    cd ..
else
    echo "📦 Building Flutter bundle..."
    cd "$UI_DIR"
    flutter build linux --debug
    cd ..

    # Copy to bundle dir for direct execution
    mkdir -p "$FLUTTER_BUNDLE_DIR/lib"
    cp "$TARGET_LIB" "$FLUTTER_BUNDLE_DIR/lib/$LIB_NAME"
    echo "✔ Updated: $FLUTTER_BUNDLE_DIR/lib/$LIB_NAME"

    echo "🚀 Running Lumen from bundle..."
    "$FLUTTER_BUNDLE_DIR"/Lumen
fi

# -----------------------------------------
# STEP 5 — Optional: Run Rust TUI backend AFTER UI closes
# -----------------------------------------
if [ "$TUI_MODE" = true ]; then
    echo "🖥️ Running Rust TUI..."
    cargo run --bin lumen
fi

echo "✨ Done."
