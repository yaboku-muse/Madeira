#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify a downloaded DXMT source-build artifact before staging four DLLs."""
import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIMARY = ('d3d10core.dll', 'd3d11.dll', 'dxgi.dll', 'winemetal.dll')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins(text):
    result = {}
    for line in text.splitlines():
        match = re.fullmatch(r' ([0-9a-f]{40}) ([^ ]+)(?: .*?)?', line)
        if not match or match[2] in result:
            raise ValueError('invalid, dirty or duplicate component pin')
        result[match[2]] = match[1]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--run-id', required=True, type=int)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    artifact = args.artifact
    if args.run_id <= 0:
        raise ValueError('invalid source run ID')
    current = subprocess.check_output(
        ['git', '-C', str(ROOT), 'submodule', 'status', '--recursive', 'wine', 'dxmt'], text=True)
    source_pins = pins((artifact / 'component-commits.txt').read_text())
    if source_pins != pins(current):
        raise ValueError('artifact Wine/DXMT pins do not match this checkout')
    commit = (artifact / 'madeira-commit.txt').read_text().strip()
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('invalid source Madeira commit')
    cross = (artifact / 'cross-arm64ec.txt').read_text()
    if 'arm64ec-w64-mingw32-clang' not in cross:
        raise ValueError('missing ARM64EC compiler provenance')
    hashes = {}
    for line in (artifact / 'module-sha256.txt').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([a-z0-9]+\.dll)', line)
        if not match or match[2] in hashes:
            raise ValueError('invalid or duplicate module checksum')
        hashes[match[2]] = match[1]
    if set(hashes) != set(PRIMARY) | {'d3d9.dll'}:
        raise ValueError('unexpected DXMT module inventory')
    spec = importlib.util.spec_from_file_location('inspect_pe', ROOT / 'tools/inspect-pe-imports.py')
    pe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pe)
    metadata = [json.loads(line) for line in (artifact / 'pe-metadata.jsonl').read_text().splitlines()]
    if len(metadata) != len(hashes) or {m['file'] for m in metadata} != set(hashes):
        raise ValueError('unexpected PE metadata inventory')
    for recorded in metadata:
        path = artifact / 'modules' / recorded['file']
        actual = pe.inspect(path)
        if actual != recorded or sha(path) != hashes[path.name]:
            raise ValueError('module hash or PE metadata mismatch: ' + path.name)
        if actual['machine'] != '0x8664' or actual['pe_magic'] != '0x20b':
            raise ValueError('unexpected PE format: ' + path.name)
    destination = ROOT / 'app/Madeira/arm64ec-windows'
    d3d9_before = sha(destination / 'd3d9.dll')
    report = {'run_id': args.run_id, 'madeira_commit': commit,
              'component_pins': source_pins,
              'staged_sha256': {name: hashes[name] for name in PRIMARY},
              'preserved_wine_d3d9_sha256': d3d9_before}
    if not args.verify_only:
        for name in PRIMARY:
            shutil.copyfile(artifact / 'modules' / name, destination / name)
            if sha(destination / name) != hashes[name]:
                raise ValueError('staged checksum mismatch: ' + name)
        if sha(destination / 'd3d9.dll') != d3d9_before:
            raise ValueError('Wine D3D9 changed during staging')
        out = ROOT / 'build/ci-output'
        out.mkdir(parents=True, exist_ok=True)
        (out / 'dxmt-staging.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
