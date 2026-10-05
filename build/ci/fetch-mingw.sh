#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
NAME=llvm-mingw-20260421-ucrt-macos-universal
SHA=bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7
mkdir -p "$R/toolchains"
if [ ! -x "$R/toolchains/$NAME/bin/arm64ec-w64-mingw32-clang" ]; then
    FILE="$R/toolchains/$NAME.tar.xz"
    curl --fail --location --retry 3 -o "$FILE" \
        "https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/$NAME.tar.xz"
    [ "$(shasum -a 256 "$FILE" | cut -d' ' -f1)" = "$SHA" ] || { echo "llvm-mingw SHA256 mismatch" >&2; exit 1; }
    tar -xJf "$FILE" -C "$R/toolchains"
fi
"$R/toolchains/$NAME/bin/arm64ec-w64-mingw32-clang" --version
