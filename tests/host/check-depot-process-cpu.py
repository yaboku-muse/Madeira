#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Run the real process CPU sampler and validate extended benchmark records."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Madeira/SwiftSteam/Content/DepotDownloader.swift').read_text(encoding='utf-8')
begin = source.index('struct ContentProcessCPUInterval {')
production = source[begin:source.index('\n}\n', begin) + 3]
code = r'''
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
'''
code += production + r'''
let interval = ContentProcessCPUInterval()
let began = ProcessInfo.processInfo.systemUptime
var value: UInt64 = 1
for _ in 0..<10000000 { value = value &* 6364136223846793005 &+ 1 }
precondition(value != 0)
let report = interval.report(wall: ProcessInfo.processInfo.systemUptime - began)
let fields = Dictionary(uniqueKeysWithValues: report.split(separator: " ").map {
    let pair = $0.split(separator: "=", maxSplits: 1); return (String(pair[0]), String(pair[1]))
})
let seconds = Double(fields["process-cpu-seconds"]!.dropLast())!
let cores = Double(fields["process-cpu-cores"]!)!
precondition(seconds.isFinite && seconds > 0 && cores.isFinite && cores >= 0)
precondition(interval.report(wall: 0) == "process-cpu=unavailable")
precondition(interval.report(wall: -1) == "process-cpu=unavailable")
precondition(interval.report(wall: .nan) == "process-cpu=unavailable")
precondition(interval.report(wall: .infinity) == "process-cpu=unavailable")
print("PASS: actual process CPU counter, average cores and invalid intervals; checksum=\(value)")
'''
swiftc = shutil.which('swiftc')
if not swiftc:
    raise SystemExit('Swift host compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('main.swift').write_text(code)
    subprocess.run([swiftc, '-O', str(path / 'main.swift'), '-o', str(path / 'probe')], check=True)
    subprocess.run([str(path / 'probe')], check=True)
    spec = importlib.util.spec_from_file_location('benchmark', root / 'tools/depot-benchmark-report.py')
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    depot = ('[steam-depot] timing depot=9001 fetched-bytes=1048576 wall=1s retries=0 '
             'process-cpu-seconds=1.25s process-cpu-cores=1.25 resume-checks=3 resume-hits=2 '
             'resume-checked-bytes=40 resume-check-sum=0.1s resume-sha1-sum=0.05s\n')
    install = ('[steam-install] timing app=9000 completed=1 fetched-bytes=1048576 wall=2s '
               'process-cpu-seconds=1.5s process-cpu-cores=0.75\n')
    log = path / 'trial.txt'
    log.write_text(depot + install)
    trial = benchmark.trial(log)
    assert trial['payload_mib_per_second'] == 1
    assert trial['depots'][0]['process_cpu']['average_cores'] == 1.25
    assert trial['depots'][0]['resume'] == {'checks': 3, 'hits': 2, 'checked_bytes': 40}
    assert trial['depots'][0]['stage_seconds']['resume-sha1-sum'] == 0.05
    assert trial['install_measurements'][0]['payload_mib_per_second'] == 0.5
    log.write_text(depot + install.replace('completed=1', 'completed=0'))
    assert benchmark.trial(log)['payload_mib_per_second'] is None
    log.write_text(install.replace('completed=1', 'completed=0'))
    assert benchmark.trial(log)['install_completed'] is False
    log.write_text('[steam-depot] timing depot=9001 fetched-bytes=0 wall=1s retries=0\n')
    trial = benchmark.trial(log)
    assert trial['payload_mib_per_second'] is None and trial['depots'][0]['process_cpu'] is None
    for invalid in [depot.replace('1.25s', 'nans'), depot.replace('resume-hits=2', 'resume-hits=4'),
                    install.replace('completed=1', 'completed=2'), install.replace('wall=2s', 'wall=0s')]:
        log.write_text(invalid)
        try:
            benchmark.trial(log)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid measurement accepted')
print('PASS: CPU/resume/whole-install parsing, old logs and incomplete-trial exclusion')
