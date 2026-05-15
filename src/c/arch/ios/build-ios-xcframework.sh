#!/usr/bin/env bash
# Cross-compiles wordgrinder (C core + bundled Lua 5.1.5 + LPeg + minizip
# + luabitop + iOS arch frontend) into a WordgrinderCore.xcframework.
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

# ---- Generate luascripts.c by running multibin2c.lua on all bundled .lua ----
echo "==> Generating luascripts.c via multibin2c.lua"
LUA_SCRIPTS=(
    "src/lua/_prologue.lua" "src/lua/colors.lua" "src/lua/events.lua"
    "src/lua/main.lua" "src/lua/xml.lua" "src/lua/utils.lua"
    "src/lua/redraw.lua" "src/lua/settings.lua" "src/lua/document.lua"
    "src/lua/forms.lua" "src/lua/ui.lua" "src/lua/browser.lua"
    "src/lua/html.lua" "src/lua/margin.lua" "src/lua/xpattern.lua"
    "src/lua/fileio.lua" "src/lua/export.lua"
    "src/lua/export/text.lua" "src/lua/export/html.lua"
    "src/lua/export/latex.lua" "src/lua/export/troff.lua"
    "src/lua/export/opendocument.lua" "src/lua/export/markdown.lua"
    "src/lua/import.lua" "src/lua/import/html.lua"
    "src/lua/import/text.lua" "src/lua/import/opendocument.lua"
    "src/lua/import/markdown.lua" "src/lua/navigate.lua"
    "src/lua/addons/goto.lua" "src/lua/addons/autosave.lua"
    "src/lua/addons/docsetman.lua" "src/lua/addons/draftmanager.lua"
    "src/lua/addons/scrapbook.lua" "src/lua/addons/statusbar_charstyle.lua"
    "src/lua/addons/statusbar_pagecount.lua" "src/lua/addons/statusbar_position.lua"
    "src/lua/addons/statusbar_wordcount.lua" "src/lua/addons/debug.lua"
    "src/lua/addons/look-and-feel.lua" "src/lua/addons/keymapoverride.lua"
    "src/lua/addons/smartquotes.lua" "src/lua/addons/undo.lua"
    "src/lua/addons/spillchocker.lua" "src/lua/addons/comments.lua"
    "src/lua/addons/templates.lua" "src/lua/addons/directories.lua"
    "src/lua/addons/recents.lua" "src/lua/addons/colorviewer.lua"
    "src/lua/addons/spriteviewer.lua" "src/lua/data/bestiary.lua"
    "src/lua/addons/bestiary.lua" "src/lua/addons/statistics.lua"
    "src/lua/addons/screens/battle-select.lua"
    "src/lua/menu.lua" "src/lua/cli.lua"
    "src/lua/lunamark/util.lua" "src/lua/lunamark/entities.lua"
    "src/lua/lunamark/markdown.lua"
)
( cd "$ROOT" && lua tools/multibin2c.lua script_table "${LUA_SCRIPTS[@]}" ) > "$INT/luascripts.c"

# ---- Source lists ----
# Lua 5.1.5 interpreter (excludes lua.c standalone main, winshim.c Windows)
LUA_SOURCES=()
for f in "$LUA_DIR"/*.c; do
    base="$(basename "$f")"
    case "$base" in
        lua.c|winshim.c) continue ;;
        *) LUA_SOURCES+=("$f") ;;
    esac
done

# Wordgrinder core (skips main.c — replicated in wg_ios.c)
CORE_SOURCES=(
    "$ROOT/src/c/lua.c"
    "$ROOT/src/c/screen.c"
    "$ROOT/src/c/utils.c"
    "$ROOT/src/c/word.c"
    "$ROOT/src/c/zip.c"
    "$ROOT/src/c/filesystem.c"
)

# Embedded support libs
EMU_SOURCES=(
    "$ROOT/src/c/emu/luabitop/lua-bitop.c"
    "$ROOT/src/c/emu/wcwidth.c"
    "$ROOT/src/c/emu/tmpnam.c"
    "$ROOT/src/c/emu/minizip/ioapi.c"
    "$ROOT/src/c/emu/minizip/zip.c"
    "$ROOT/src/c/emu/minizip/unzip.c"
    "$ROOT/src/c/emu/lpeg/lpvm.c"
    "$ROOT/src/c/emu/lpeg/lpcap.c"
    "$ROOT/src/c/emu/lpeg/lptree.c"
    "$ROOT/src/c/emu/lpeg/lpcode.c"
    "$ROOT/src/c/emu/lpeg/lpprint.c"
)

# iOS arch frontend
IOS_SOURCES=(
    "$SRC/wg_ios.c"
    "$SRC/dpy.c"
    "$INT/luascripts.c"
)

SOURCES=("${IOS_SOURCES[@]}" "${CORE_SOURCES[@]}" "${EMU_SOURCES[@]}" "${LUA_SOURCES[@]}")

INCLUDES=(
    -I"$ROOT/src/c"
    -I"$LUA_DIR"
    -I"$ROOT/src/c/emu/minizip"
    -I"$ROOT/src/c/emu/lpeg"
    -I"$ROOT/src/c/emu/uthash"
    -I"$ROOT/src/c/emu/luabitop"
    -I"$SRC"
)

DEFINES=(
    -DVERSION='"0.8"'
    -DFILEFORMAT=8
    -DARCH='"ios"'
)

compile_one() {
    local sdk="$1" target="$2" outdir="$3"
    local sdkroot
    sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    local count=0
    for src in "${SOURCES[@]}"; do
        local base
        base="$(basename "${src%.c}")"
        local dir
        dir="$(dirname "$src")"
        # Disambiguate same-name files (e.g., zip.c in core vs minizip)
        local objname="${base}__$(echo "$dir" | tr '/' '_' | tr -c '[:alnum:]_' '_').o"
        xcrun --sdk "$sdk" clang \
            -isysroot "$sdkroot" \
            -target "$target" \
            -fembed-bitcode-marker \
            -O2 -fobjc-arc \
            "${INCLUDES[@]}" \
            "${DEFINES[@]}" \
            -c "$src" \
            -o "$outdir/$objname"
        count=$((count + 1))
    done
    echo "    compiled $count files for $target"
}

compile_one iphoneos        "arm64-apple-ios${DEPLOY}"               "$INT/device"
compile_one iphonesimulator "arm64-apple-ios${DEPLOY}-simulator"     "$INT/sim-arm64"
compile_one iphonesimulator "x86_64-apple-ios${DEPLOY}-simulator"    "$INT/sim-x86_64"

xcrun libtool -static -o "$INT/device/$LIB_NAME.a"     "$INT/device"/*.o
xcrun libtool -static -o "$INT/sim-arm64/$LIB_NAME.a"  "$INT/sim-arm64"/*.o
xcrun libtool -static -o "$INT/sim-x86_64/$LIB_NAME.a" "$INT/sim-x86_64"/*.o

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
