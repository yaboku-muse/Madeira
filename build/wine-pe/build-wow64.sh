#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
# Rebuild the native ARM64 Wine side of WOW64 into an isolated evidence folder.
# This does not stage replacements in the app or assert device compatibility.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
export PATH="$(brew --prefix bison)/bin:$TC:$PATH"
B="$R/wine/build-wow64-pe"
OUT="$R/build/ci-output/wine-wow64"
mkdir -p "$B" "$OUT"
if [ ! -f "$B/config.status" ]; then
    (cd "$B" && ../configure --enable-archs=aarch64 --without-x --without-vulkan \
        --without-freetype --without-gnutls --disable-tests --enable-winegstreamer)
fi
make -C "$B" -j2 include/all \
    dlls/ntdll/aarch64-windows/ntdll.dll \
    dlls/wow64/aarch64-windows/wow64.dll \
    dlls/wow64win/aarch64-windows/wow64win.dll
for module in ntdll wow64 wow64win; do
    "$TC/aarch64-w64-mingw32-strip" --strip-debug \
        -o "$OUT/$module.dll" "$B/dlls/$module/aarch64-windows/$module.dll"
done
python3 "$R/tools/inspect-pe-imports.py" "$OUT/ntdll.dll" "$OUT/wow64.dll" "$OUT/wow64win.dll" > "$OUT/pe-metadata.jsonl"
python3 - "$OUT/pe-metadata.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding='utf-8')]
assert len(rows) == 3
assert all(row['machine'] == '0xaa64' and row['pe_magic'] == '0x20b' for row in rows), 'unexpected WOW64 host architecture'
PY
git -C "$R" rev-parse HEAD > "$OUT/madeira-commit.txt"
git -C "$R" submodule status wine > "$OUT/wine-commit.txt"
(cd "$OUT" && shasum -a 256 ntdll.dll wow64.dll wow64win.dll > SHA256SUMS)
