#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
# Rebuild pinned DXMT ARM64EC DLLs into isolated output for verification.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
export PATH="$(brew --prefix bison)/bin:$TC:$PATH"
W="$R/wine/build-dxmt-arm64ec"
D="$R/dxmt/build-arm64ec"
OUT="$R/build/ci-output/dxmt-arm64ec"
mkdir -p "$W" "$OUT/modules"
if [ ! -f "$W/config.status" ]; then
    (cd "$W" && ../configure --enable-archs=arm64ec --without-x --without-vulkan \
        --without-freetype --without-gnutls --disable-tests)
fi
make -C "$W" -j2 include/all libs/winecrt0/arm64ec-windows/libwinecrt0.a \
    dlls/ntdll/arm64ec-windows/libntdll.a dlls/dbghelp/arm64ec-windows/libdbghelp.a
X="$OUT/cross-arm64ec.txt"
python3 - "$R/dxmt/build-arm64ec-win.txt" "$X" "$R" <<'PY'
from pathlib import Path
import sys
source, output, root = map(Path, sys.argv[1:])
output.write_text(source.read_text().replace('@GLOBAL_SOURCE_ROOT@', str(root)))
PY
if [ ! -f "$D/build.ninja" ]; then
    (cd "$R/dxmt" && SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
        meson setup --cross-file "$X" --native-file build-osx.txt --buildtype release \
        -Dwine_build_path="$W" -Dwine_builtin_dll=true build-arm64ec)
fi
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" meson compile -C "$D" -j2
for image in d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll \
    winemetal/winemetal.dll d3d9/d3d9.dll; do
    "$TC/arm64ec-w64-mingw32-strip" --strip-debug \
        -o "$OUT/modules/$(basename "$image")" "$D/src/$image"
done
python3 "$R/tools/inspect-pe-imports.py" "$OUT"/modules/* > "$OUT/pe-metadata.jsonl"
git -C "$R" rev-parse HEAD > "$OUT/madeira-commit.txt"
git -C "$R" submodule status --recursive wine dxmt > "$OUT/component-commits.txt"
(cd "$OUT/modules" && shasum -a 256 * > ../module-sha256.txt)
