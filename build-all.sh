#!/bin/bash
set -e

# Build script for zigup - cross-compile for all platforms

VERSION=${1:-dev}
BUILD_DIR="dist"
OPTIMIZE="ReleaseSafe"

echo "Building zigup $VERSION for all platforms..."

# Clean and create dist directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Define targets
declare -a TARGETS=(
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-macos"
    "aarch64-macos"
)

# Build for each target
for target in "${TARGETS[@]}"; do
    echo "Building for $target..."
    zig build -Dtarget="$target" -Doptimize="$OPTIMIZE"
    cp zig-out/bin/zigup "$BUILD_DIR/zigup-$target"
done

echo ""
echo "Build complete! Binaries in $BUILD_DIR/:"
ls -lh "$BUILD_DIR"
