#!/bin/bash
# Start the Lumen app (Rust backend + Flutter UI)
set -e

# Build Rust core as shared library
cd "$(dirname "$0")/lumen/core"
echo "Building Rust core..."
cargo build --release

# Copy shared library to Flutter UI dir
LIBNAME="liblumen_core.so"
cp target/release/$LIBNAME ../ui/$LIBNAME

# Start Flutter UI
cd ../ui
echo "Setting LD_LIBRARY_PATH for Rust FFI..."
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH

echo "Running Flutter app..."
flutter run
