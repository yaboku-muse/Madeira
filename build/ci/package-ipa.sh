#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
# Build Debug for the physical iOS device, then create an ad-hoc signed IPA
# for normal sideloading tools to re-sign. No Apple account or profile is used.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$R/build/ci-output"
mkdir -p "$OUT" "$R/app/Madeira/x86_64-vcruntime"
# Microsoft runtime binaries are supplied by the user, never imported from an
# unrelated installation into this public diagnostic build.
cp "$R/tools/fetch-vcruntime.md" "$R/app/Madeira/x86_64-vcruntime/README.md"
bash "$R/build/stage-licenses.sh"
python3 - "$R" <<'PY'
from pathlib import Path
import sys
r = Path(sys.argv[1])
assert b'[pe-image]' in (r / 'app/Madeira/arm64ec-windows/ntdll.dll').read_bytes(), 'diagnostic ntdll was not staged'
assert 'MADEIRA_STEAM_HOST_LAUNCH_OPTION'.encode('utf-16le') in (r / 'app/Madeira/arm64ec-windows/dockhost.exe').read_bytes(), 'updated Dock was not staged'
PY
xcodebuild -project "$R/app/Madeira.xcodeproj" -scheme Madeira \
    -configuration Debug -destination 'generic/platform=iOS' \
    -derivedDataPath "$R/build/xcode-derived" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
    MADEIRA_BUNDLE_IDENTIFIER=com.willfaust.madeora \
    CURRENT_PROJECT_VERSION=100 build 2>&1 | tee "$OUT/xcodebuild.log"
APP="$R/build/xcode-derived/Build/Products/Debug-iphoneos/Madeira.app"
test -f "$APP/Madeira"
# BuildStamp already displays/logs MadeiraBuild. Stamp the packaged app before
# signing so device logs identify the exact source instead of every diagnostic
# appearing as the same v0.1.3 (100). This contains no signing/account data.
python3 - "$R" "$APP" <<'PY'
from pathlib import Path
import plistlib, subprocess, sys
r, app = map(Path, sys.argv[1:])
commit = subprocess.check_output(['git', '-C', str(r), 'rev-parse', 'HEAD'], text=True).strip()
path = app / 'Info.plist'
info = plistlib.loads(path.read_bytes())
info['MadeiraSourceCommit'] = commit
info['MadeiraBuild'] = f"v{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}) source={commit}"
path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
PY
# Sign embedded code from the inside out with an ad-hoc identity. This keeps
# the requested JIT/Memory+ entitlements readable to the user's re-signing tool.
while IFS= read -r lib; do codesign --force --sign - --timestamp=none "$lib"; done < <(find "$APP" -type f -name '*.dylib')
while IFS= read -r framework; do codesign --force --sign - --timestamp=none "$framework"; done < <(find "$APP" -type d -name '*.framework')
while IFS= read -r extension; do codesign --force --sign - --timestamp=none "$extension"; done < <(find "$APP" -type d -name '*.appex')
codesign --force --sign - --timestamp=none --entitlements "$R/app/Madeira/Madeira.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
python3 - "$R" "$APP" "$OUT" <<'PY'
from pathlib import Path
import hashlib, json, plistlib, subprocess, sys
r, app, out = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.willfaust.madeora', 'Madeira update identity changed'
helper_plist = app / 'PlugIns/MadeiraJITHelper.appex/Info.plist'
if helper_plist.exists():
    helper = plistlib.loads(helper_plist.read_bytes())
    assert helper['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.JITHelper', 'JIT helper identity changed'
    assert info['CFBundleVersion'] == helper['CFBundleVersion'] == '100', 'app/helper build versions differ'
assert not list(app.rglob('embedded.mobileprovision')), 'unexpected provisioning profile'
assert not list(app.rglob('*.p12')), 'unexpected signing identity'
ent = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
assert ent.get('com.apple.developer.kernel.increased-memory-limit') is True
assert 'com.apple.developer.kernel.extended-virtual-addressing' not in ent
def git(*args):
    return subprocess.check_output(['git', '-C', str(r), *args], text=True).strip()
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
report = {
    'purpose': 'diagnostic device test; gameplay acceptance pending',
    'madeira_commit': git('rev-parse', 'HEAD'),
    'build_stamp': info['MadeiraBuild'],
    'submodules': git('submodule', 'status', '--recursive').splitlines(),
    'configuration': 'Debug',
    'bundle_identifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'],
    'build_number': info['CFBundleVersion'],
    'update_signing_requirement': 're-sign with the installed app bundle identifier and App ID prefix',
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'sdk': subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip(),
    'ntdll_sha256': sha(app / 'arm64ec-windows/ntdll.dll'),
    'dockhost_sha256': sha(app / 'arm64ec-windows/dockhost.exe'),
    'signing': 'ad-hoc; re-sign before installing',
    'entitlements': ent,
    'microsoft_runtime_binaries_included': False,
    'unchanged_PE_components': 'tracked upstream binaries; complete clean PE rebuild pending',
}
assert info['MadeiraSourceCommit'] == report['madeira_commit'], 'packaged build source stamp mismatch'
assert info['MadeiraBuild'].endswith('source=' + report['madeira_commit']), 'packaged build label mismatch'
staging = out / 'dxmt-staging.json'
if staging.exists():
    graphics = json.loads(staging.read_text())
    for name, expected in graphics['staged_sha256'].items():
        assert sha(app / 'arm64ec-windows' / name) == expected, f'packaged DXMT mismatch: {name}'
    assert sha(app / 'arm64ec-windows/d3d9.dll') == graphics['preserved_wine_d3d9_sha256'], 'packaged Wine D3D9 changed'
    report['source_built_dxmt'] = graphics
    report['unchanged_PE_components'] = 'tracked upstream binaries except rebuilt ntdll, Dock and four DXMT graphics DLLs; complete clean PE rebuild pending'
(out / 'build-provenance.json').write_text(json.dumps(report, indent=2) + '\n')
PY
PACKAGE="$(mktemp -d "$OUT/package.XXXXXX")"
mkdir "$PACKAGE/Payload"
ditto "$APP" "$PACKAGE/Payload/Madeira.app"
NAME="Madeira-diagnostic-$(git -C "$R" rev-parse --short HEAD).ipa"
(cd "$PACKAGE" && ditto -c -k --keepParent Payload "$OUT/$NAME")
(cd "$OUT" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Built $OUT/$NAME; this IPA must be re-signed by the user's sideloading tool."
