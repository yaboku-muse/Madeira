#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
# Rebuild Wine-owned images from the tracked ARM64EC farm into isolated output.
# Other component owners and images without Wine source are recorded, not copied.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
export PATH="$(brew --prefix bison)/bin:$TC:$PATH"
B="$R/wine/build-arm64ec-farm"
OUT="$R/build/ci-output/wine-arm64ec"
mkdir -p "$B" "$OUT/modules"
if [ ! -f "$B/config.status" ]; then
    (cd "$B" && ../configure --enable-archs=arm64ec --without-x --without-vulkan \
        --without-freetype --without-gnutls --disable-tests --enable-winegstreamer)
fi
# WIDL's ARM64EC typelib imports look in the aarch64 directory in this fork.
mkdir -p "$B/dlls/stdole2.tlb"
[ -e "$B/dlls/stdole2.tlb/aarch64-windows" ] || [ -L "$B/dlls/stdole2.tlb/aarch64-windows" ] \
    || ln -s arm64ec-windows "$B/dlls/stdole2.tlb/aarch64-windows"
python3 - "$R" "$B" "$OUT" <<'PY'
import json, re, sys
from pathlib import Path
root, build, out = map(Path, sys.argv[1:])
owners = {'d3d10core.dll': 'DXMT', 'd3d11.dll': 'DXMT', 'dxgi.dll': 'DXMT',
          'winemetal.dll': 'DXMT',
          'd3d12.dll': 'Madeira D3D12', 'd3d12core.dll': 'Madeira D3D12',
          'madeira_d3d12.dll': 'Madeira D3D12', 'xtajit64.dll': 'FEX'}
rules = re.findall(r'^(?:dlls|programs)/[^/\s]+/arm64ec-windows/[^/:\s]+',
                   (build / 'Makefile').read_text(), re.M)
targets = {}
for rule in rules:
    name = Path(rule).name.lower()
    if Path(name).suffix not in ('.dll', '.exe', '.drv', '.cpl', '.acm', '.ax', '.ocx'):
        continue
    if name in targets and targets[name] != rule:
        raise SystemExit('ambiguous ARM64EC target: ' + name)
    targets[name] = rule
selected, excluded = [], []
for path in sorted((root / 'app/Madeira/arm64ec-windows').iterdir()):
    if path.suffix.lower() not in ('.dll', '.exe', '.drv', '.cpl', '.acm', '.ax', '.ocx'):
        continue
    name = path.name.lower()
    if name in owners:
        excluded.append({'image': path.name, 'reason': owners[name]})
    elif name in targets:
        selected.append({'image': path.name, 'target': targets[name]})
    else:
        excluded.append({'image': path.name, 'reason': 'no configured Wine ARM64EC file target'})
# The tracked bthprops.cpl imports this DLL, but the baseline farm omits it.
# Build the pinned Wine implementation alongside the farm; do not substitute a
# downloaded DLL or silently drop bthprops. App staging remains a separate gate.
for name, required_by in [('bluetoothapis.dll', 'bthprops.cpl')]:
    if name not in targets:
        raise SystemExit('missing configured Wine dependency target: ' + name)
    if not any(row['image'].lower() == name for row in selected):
        selected.append({'image': name, 'target': targets[name],
                         'reason': 'direct import of ' + required_by})
if not selected:
    raise SystemExit('no Wine farm targets selected')
(out / 'selection.json').write_text(json.dumps({'wine_images': selected, 'excluded_images': excluded}, indent=2) + '\n')
(out / 'targets.txt').write_text('\n'.join(row['target'] for row in selected) + '\n')
print(f'Selected {len(selected)} Wine images; recorded {len(excluded)} separate or unavailable images.')
PY
TARGETS=()
while IFS= read -r target; do TARGETS+=("$target"); done < "$OUT/targets.txt"
if ! make -C "$B" -j2 include/all "${TARGETS[@]}" > "$B/madeira-arm64ec-build.log" 2>&1; then
    tail -n 80 "$B/madeira-arm64ec-build.log"
    exit 1
fi
for target in "${TARGETS[@]}"; do
    "$TC/arm64ec-w64-mingw32-strip" --strip-debug -o "$OUT/modules/$(basename "$target")" "$B/$target"
done
python3 "$R/tools/inspect-pe-imports.py" "$OUT"/modules/* > "$OUT/pe-metadata.jsonl"
git -C "$R" rev-parse HEAD > "$OUT/madeira-commit.txt"
git -C "$R" submodule status wine > "$OUT/wine-commit.txt"
(cd "$OUT/modules" && shasum -a 256 * > ../module-sha256.txt)
