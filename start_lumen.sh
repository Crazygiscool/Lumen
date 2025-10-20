#!/bin/bash
# Start the Lumen app (Rust backend + Flutter UI)
set -e

echo "🔍 Checking environment..."

# Check for Clang
if ! command -v clang &> /dev/null; then
    echo "Clang not found. Installing..."
    if [ -x "$(command -v apt)" ]; then
        sudo apt update && sudo apt install -y clang
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y clang
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -Sy clang
    else
        echo "❌ Unsupported package manager. Please install Clang manually from https://releases.llvm.org/download.html"
        exit 1
    fi
else
    echo "✅ Clang is installed."
fi

# Check for CMake
if ! command -v cmake &> /dev/null; then
    echo "CMake not found. Installing..."
    if [ -x "$(command -v apt)" ]; then
        sudo apt update && sudo apt install -y cmake
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y cmake
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -Sy cmake
    else
        echo "❌ Unsupported package manager. Please install CMake manually from https://cmake.org/download/"
        exit 1
    fi
else
    echo "✅ CMake is installed."
fi


# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "Rust not found. Installing via rustup..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "✅ Rust is installed."
fi

# Check for Flutter
if ! command -v flutter &> /dev/null; then
    echo "Flutter not found. Installing Flutter SDK..."

    if [ -x "$(command -v apt)" ]; then
        echo "Detected Debian/Ubuntu. Installing via apt..."
        sudo apt update && sudo apt install -y flutter
    elif [ -x "$(command -v dnf)" ]; then
        echo "Detected Fedora. Installing via dnf..."
        sudo dnf install -y flutter
    elif [ -x "$(command -v pacman)" ]; then
        echo "Detected Arch Linux. Installing Flutter via AUR..."
        if ! command -v yay &> /dev/null; then
            echo "Installing yay (AUR helper)..."
            sudo pacman -S yay
        fi
        yay -S flutter
    else
        echo "⚠️ No known package manager detected. Falling back to manual install..."
        FLUTTER_DIR="$HOME/flutter"
        git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
        export PATH="$FLUTTER_DIR/bin:$PATH"
    fi
else
    echo "✅ Flutter is installed."
fi

# Optional: Check for flutter_rust_bridge_codegen
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen
fi

echo "🛠 Building Rust core..."
cd "$(dirname "$0")/lumen/core"
cargo build --release

echo "📦 Copying shared library to Flutter UI..."
LIBNAME="liblumen_core.so"
cp target/release/$LIBNAME ../ui/$LIBNAME

echo "🚀 Starting Flutter UI..."
cd ../ui
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH
flutter run
