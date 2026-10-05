#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Verify pinned Valve packages, upgrade metadata and production Swift extraction.

Archives stay in ignored build output; only diagnostic text is uploaded by CI.
No Steam library is executed and no account or credentials are used.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import sys
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Madeira/SteamRuntime.swift').read_text(encoding='utf-8')
cache = root / 'build/ci-output/steam-runtime-packages'
cache.mkdir(parents=True, exist_ok=True)
origin = 'https://client-update.akamai.steamstatic.com/'
current = re.findall(r'Package\(file: "([^"]+)", bytes: ([0-9_]+),\s*sha256: "([0-9a-f]{64})"\)', source)
assert len(current) == 3
legacy = [
    ('bins_win32.zip.23e34a6d4b10596a44561a5100dac5585d2517da', '59544006', '8b712b2a3412a9066b7725f4e1c5cef9a7ca5b187b6585a5b92d25d09df0ba62'),
    ('bins_win64_win32.zip.f29d67dc38a4be027f1734802697c668621a6da1', '10509550', '345f6e4bdc19b27ae53bf752c21e2d894e0e899d94823222fb426e890d1226b5'),
    ('steam_win32.zip.3e96965d109fc2d4cc14206b2fc4ec960a746ed3', '2307664', '1369615c795b60de822876b4dc4042186cf58d0dc8f63ea1371167f667e16925'),
]


def fetch(pins):
    inventory = {}
    paths = []
    for name, size, digest in pins:
        assert '/' not in name and '\\' not in name and '..' not in name
        expected_size = int(size.replace('_', ''))
        path = cache / name
        if not path.exists():
            with urllib.request.urlopen(origin + name, timeout=60) as response:
                assert response.geturl() == origin + name, 'unexpected Valve package redirect'
                data = response.read(expected_size + 1)
            assert len(data) == expected_size and hashlib.sha256(data).hexdigest() == digest
            path.write_bytes(data)
        data = path.read_bytes()
        assert len(data) == expected_size and hashlib.sha256(data).hexdigest() == digest
        print('PASS: verified Valve package', name, digest, flush=True)
        paths.append(str(path))
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            for entry in archive.infolist():
                if entry.is_dir():
                    continue
                key = entry.filename.replace('\\', '/').lower()
                assert key not in inventory, 'cross-package duplicate'
                inventory[key] = hashlib.sha256(archive.read(entry)).hexdigest()
    return inventory, paths


def metadata(field):
    block = source[source.index('static let ' + field):]
    block = block[:block.index('\n    ]')]
    return dict(re.findall(r'"([^"]+)": "([a-f0-9]{64})"', block))


old, _ = fetch(legacy)
new, paths = fetch(current)
recorded_old = metadata('legacyFileSHA256')
assert recorded_old == {name: old[name] for name in new.keys() & old.keys()}, 'legacy replacement metadata differs from verified Valve bytes'
critical = metadata('criticalFileSHA256')
assert len(critical) == 10
assert all(new.get(name.lower()) == digest for name, digest in critical.items()), 'critical runtime metadata mismatch'
print('PASS: all legacy replacement and critical runtime hashes match official archives', flush=True)
subprocess.run([sys.executable, str(root / 'tests/host/check-dock-components.py'), *paths], cwd=root, check=True)
