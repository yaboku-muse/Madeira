#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Read-only package checks before release/USB copy; not a device or signing test."""
import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from pathlib import Path, PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(ipa, provenance, checksum, commit):
    require(re.fullmatch(r'[0-9a-f]{40}', commit), 'expected commit must be a full Git hash')
    report = json.loads(provenance.read_text(encoding='utf-8'))
    require(report['madeira_commit'] == commit, 'provenance commit mismatch')
    with ipa.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    require(checksum.read_text(encoding='utf-8').split()[0].lower() == digest, 'IPA checksum mismatch')
    prefix = 'Payload/Madeira.app/'
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'duplicate ZIP members')
        for name in names:
            path = PurePosixPath(name)
            require(not path.is_absolute() and '..' not in path.parts and '\\' not in name,
                    'unsafe ZIP member')
            require(not name.lower().endswith(('.p12', '.mobileprovision')), 'unexpected signing material')
        require(archive.testzip() is None, 'ZIP CRC failure')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        if 'build_stamp' in report:
            require(info.get('MadeiraSourceCommit') == commit, 'packaged source stamp mismatch')
            require(info.get('MadeiraBuild') == report['build_stamp'] and
                    report['build_stamp'].endswith('source=' + commit), 'packaged build label mismatch')
        helper = plistlib.loads(archive.read(prefix + 'PlugIns/MadeiraJITHelper.appex/Info.plist'))
        require(info['CFBundleIdentifier'] == 'com.willfaust.madeora', 'upstream app identity changed')
        require(helper['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.JITHelper', 'helper identity mismatch')
        require(info['CFBundleVersion'] == helper['CFBundleVersion'] == '100', 'diagnostic build version mismatch')
        require(archive.getinfo(prefix + info['CFBundleExecutable']).file_size > 0, 'missing app executable')
        for filename, key, marker in [
            ('ntdll.dll', 'ntdll_sha256', b'[pe-image]'),
            ('dockhost.exe', 'dockhost_sha256', 'MADEIRA_STEAM_HOST_LAUNCH_OPTION'.encode('utf-16le')),
        ]:
            data = archive.read(prefix + 'arm64ec-windows/' + filename)
            require(hashlib.sha256(data).hexdigest() == report[key], filename + ' provenance mismatch')
            require(marker in data, filename + ' diagnostic marker missing')
        graphics = report.get('source_built_dxmt')
        if graphics is not None:
            require(set(graphics['staged_sha256']) == {'d3d10core.dll', 'd3d11.dll', 'dxgi.dll', 'winemetal.dll'},
                    'unexpected source-built graphics inventory')
            pins = {}
            for line in report['submodules']:
                # The provenance writer strips outer whitespace from git output,
                # so only its first initialized entry may lose the leading space.
                match = re.fullmatch(r' ?([0-9a-f]{40}) ([^ ]+)(?: .*?)?', line)
                require(match is not None, 'uninitialized or changed package component pin')
                pins[match[2]] = match[1]
            require(all(pins.get(name) == commit for name, commit in graphics['component_pins'].items()),
                    'graphics source pins differ from package pins')
            for filename, expected in graphics['staged_sha256'].items():
                data = archive.read(prefix + 'arm64ec-windows/' + filename)
                require(hashlib.sha256(data).hexdigest() == expected, filename + ' graphics provenance mismatch')
            wine_d3d9 = archive.read(prefix + 'arm64ec-windows/d3d9.dll')
            require(hashlib.sha256(wine_d3d9).hexdigest() == graphics['preserved_wine_d3d9_sha256'],
                    'Wine D3D9 was replaced during graphics staging')
    return {'ipa': ipa.name, 'sha256': digest, 'madeira_commit': commit,
            'bundle_identifier': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build_number': info['CFBundleVersion'],
            'package_checks': 'passed', 'signing_verification': 'requires macOS codesign verification',
            'installation_and_gameplay': 'requires physical device testing'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--provenance', type=Path, required=True)
    parser.add_argument('--checksum', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.ipa, args.provenance, args.checksum, args.expected_commit), indent=2))
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Package verification failed: {error}\n')


if __name__ == '__main__':
    main()
