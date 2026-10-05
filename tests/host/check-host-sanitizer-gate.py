#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 125hz
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise actual CI status propagation with recovering sanitizer diagnostics."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile

runner = Path(__file__).resolve().parents[2] / 'build/ci/host-regressions.py'
with tempfile.TemporaryDirectory(prefix='madeira-host-gate-') as name:
    root = Path(name)
    (root / 'build/ci').mkdir(parents=True)
    (root / 'tests/host').mkdir(parents=True)
    shutil.copy2(runner, root / 'build/ci/host-regressions.py')
    for name in ['check-jit-network.py', 'check-steam-cloud.py', 'check-depot-network-metrics.py', 'check-depot-native-control.py', 'check-mach-stp-alias.py']:
        (root / 'tests/host' / name).write_text('pass\n')
    for name, output, code in [
        ('check-a-clean.py', 'PASS: clean', 0),
        ('check-b-recover.py', 'probe.c:105:31: runtime error: index 1879048704 out of bounds', 0),
        ('check-c-tsan.py', 'WARNING: ThreadSanitizer: data race', 0),
        ('check-d-failed.py', 'unrelated subprocess failure', 7),
        ('check-e-last.py', 'PASS: remaining check still runs', 0),
    ]:
        (root / 'tests/host' / name).write_text(f'print({output!r})\nraise SystemExit({code})\n')
    result = subprocess.run([sys.executable, str(root / 'build/ci/host-regressions.py'), '--platform', 'linux'], text=True, capture_output=True)
    assert result.returncode == 1, result.stdout + result.stderr
    rows = json.loads((root / 'build/ci-output/host-tests/results.json').read_text())
    assert [row['exit_code'] for row in rows] == [0, 1, 1, 7, 0], rows
    assert [row['process_exit_code'] for row in rows] == [0, 0, 0, 7, 0], rows
    assert [row['sanitizer_errors'] for row in rows] == [False, True, True, False, False], rows
    assert (root / 'build/ci-output/host-tests/check-b-recover.log').read_text().startswith('probe.c:105:31: runtime error:')
    assert 'PASS check-e-last.py' in result.stdout
print('PASS: actual CI runner rejects zero-exit UBSan/TSan diagnostics, retains raw statuses and continues remaining checks')
