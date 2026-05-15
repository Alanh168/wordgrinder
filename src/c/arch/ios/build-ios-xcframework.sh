#!/usr/bin/env bash
# Phase 0 stub: cross-compiles the iOS arch stub into WordgrinderCore.xcframework.
# Expands in Phase 2 to include wordgrinder's core C + bundled Lua.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SRC="$ROOT/src/c/arch/ios"
LUA_DIR="$ROOT/src/c/emu/lua-5.1.5"
OUT="$ROOT/build/ios"
INT="$OUT/intermediates"
HEADERS="$OUT/headers"
DEPLOY="26.0"
FRAMEWORK_NAME="WordgrinderCore"
LIB_NAME="libwordgrinder-ios"

rm -rf "$OUT/$FRAMEWORK_NAME.xcframework" "$INT"
mkdir -p "$INT/device" "$INT/sim-arm64" "$INT/sim-x86_64" "$HEADERS"

cp "$SRC/wg_ios.h" "$HEADERS/"
cp "$SRC/module.modulemap" "$HEADERS/"

# Source list: iOS arch + bundled Lua 5.1.5 interpreter.
# Excluded: lua.c (standalone interpreter main()), winshim.c (Windows-only).
SOURCES=("$SRC/wg_ios.c")
for f in "$LUA_DIR"/*.c; do
    base="$(basename "$f")"
    case "$base" in
        lua.c|winshim.c) continue ;;
        *) SOURCES+=("$f") ;;
    esac
done

compile_one() {
    local sdk="$1" target="$2" outdir="$3"
    local sdkroot
    sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    for src in "${SOURCES[@]}"; do
        local base
        base="$(basename "${src%.c}")"
        xcrun --sdk "$sdk" clang \
            -isysroot "$sdkroot" \
            -target "$target" \
            -fembed-bitcode-marker \
            -O2 -fobjc-arc \
            -I"$SRC" \
            -I"$LUA_DIR" \
            -c "$src" \
            -o "$outdir/$base.o"
    done
}

compile_one iphoneos        "arm64-apple-ios${DEPLOY}"               "$INT/device"
compile_one iphonesimulator "arm64-apple-ios${DEPLOY}-simulator"     "$INT/sim-arm64"
compile_one iphonesimulator "x86_64-apple-ios${DEPLOY}-simulator"    "$INT/sim-x86_64"

# Archive each slice
xcrun libtool -static -o "$INT/device/$LIB_NAME.a"     "$INT/device"/*.o
xcrun libtool -static -o "$INT/sim-arm64/$LIB_NAME.a"  "$INT/sim-arm64"/*.o
xcrun libtool -static -o "$INT/sim-x86_64/$LIB_NAME.a" "$INT/sim-x86_64"/*.o

# Fat archive for the simulator (arm64 + x86_64)
lipo -create \
    "$INT/sim-arm64/$LIB_NAME.a" \
    "$INT/sim-x86_64/$LIB_NAME.a" \
    -output "$INT/$LIB_NAME-sim.a"

xcodebuild -create-xcframework \
    -library "$INT/device/$LIB_NAME.a"   -headers "$HEADERS" \
    -library "$INT/$LIB_NAME-sim.a"      -headers "$HEADERS" \
    -output "$OUT/$FRAMEWORK_NAME.xcframework"

echo
echo "Built: $OUT/$FRAMEWORK_NAME.xcframework"
