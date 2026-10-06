#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
#
# Build Madeira Dock for Ubisoft (dockhost-ubi) as a stripped x86-64 PE and
# stage it in the app bundle:
#   app/Madeira/arm64ec-windows/dockhost-ubi.exe
#
# dockhost-ubi.exe drives Ubisoft Connect the way dockhost.exe drives Steam:
# it takes a Ubisoft session ticket from a one-use auth handoff, ensures the
# real Connect client (upc.exe) is running, and fires the uplay://launch/
# URL to start the game. It does not reimplement the client.
#
# Usage: build/madeira-dock-ubi/build.sh
# LLVM_MINGW=<dir with x86_64-w64-mingw32-clang> overrides the toolchain.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
SRC="$DIR/src"
MINGW="${LLVM_MINGW:-$REPO_ROOT/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin}"
CC="$MINGW/x86_64-w64-mingw32-clang"
OUT="$REPO_ROOT/app/Madeira/arm64ec-windows"

[ -f "$SRC/main.c" ] || { echo "dockhost-ubi sources missing: $SRC" >&2; exit 1; }
[ -x "$CC" ] || { echo "missing cross compiler: $CC (set LLVM_MINGW)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Same flags as the Steam Dock host: warnings are errors, static runtime,
# stripped, reproducible (no timestamp).
"$CC" -std=c11 -O2 -Wall -Wextra -Werror -Wno-cast-function-type \
    -static -Wl,--strip-all -Wl,--no-insert-timestamp \
    -o "$TMP/dockhost-ubi.exe" "$SRC"/*.c -ladvapi32 -lshell32 -lwinhttp

mkdir -p "$OUT"
cp "$TMP/dockhost-ubi.exe" "$OUT/"
if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$OUT/dockhost-ubi.exe"; else sha256sum "$OUT/dockhost-ubi.exe"; fi
ls -la "$OUT/dockhost-ubi.exe"
