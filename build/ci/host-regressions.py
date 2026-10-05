#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Run the existing host checks independently and retain every result."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
out = root / "build/ci-output/host-tests"
out.mkdir(parents=True, exist_ok=True)
results = []
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['linux', 'macos'], required=True)
platform = parser.parse_args().platform
# These checks require Apple SDK modules (Darwin and CryptoKit) or native
# ARM/LSE2 paired-store execution. The Steam library harness supplies Linux crypto/compression shims
# that conflict with the Apple SDK, so it belongs with the Linux checks.
apple_checks = {'check-jit-network.py', 'check-steam-cloud.py', 'check-depot-network-metrics.py', 'check-depot-native-control.py', 'check-mach-stp-alias.py'}
tests = sorted((root / "tests/host").glob("check-*.py"))
assert apple_checks <= {test.name for test in tests}, 'Apple test inventory changed'
selected = [test for test in tests if (test.name in apple_checks) == (platform == 'macos')]
sanitizer_failure = re.compile(
    r'\bruntime error:|\b(?:ERROR|WARNING|SUMMARY): (?:Address|UndefinedBehavior|Thread|Leak|Memory)Sanitizer')
for test in selected:
    started = time.monotonic()
    log = out / f"{test.stem}.log"
    with log.open("w") as stream:
        try:
            result = subprocess.run([sys.executable, str(test)], cwd=root,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
            stream.write("\nHost check exceeded 600 seconds.\n")
    # Recovering UBSan can report undefined behavior and still return zero.
    # Retain the actual subprocess status, but refuse a green CI result when
    # its captured output contains a sanitizer diagnostic.
    log_text = log.read_text(errors="replace")
    process_code = code
    sanitizer_errors = bool(sanitizer_failure.search(log_text))
    if code == 0 and sanitizer_errors:
        code = 1
    elapsed = round(time.monotonic() - started, 2)
    results.append({"test": test.name, "exit_code": code, "process_exit_code": process_code,
                    "sanitizer_errors": sanitizer_errors, "seconds": elapsed})
    print(f"{'PASS' if code == 0 else 'FAIL'} {test.name} ({elapsed}s)", flush=True)
    if code:
        print("\n".join(log_text.splitlines()[-25:]), flush=True)
(out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
sys.exit(0 if results and all(result["exit_code"] == 0 for result in results) else 1)
