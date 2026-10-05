#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile the production tuning policy and exercise throughput/load changes."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Madeira/SwiftSteam/Content/DepotDownloader.swift').read_text()
policy = 'struct ContentConcurrency {' + source.split('struct ContentConcurrency {', 1)[1].split('/// Chunk-request measurements', 1)[0]
health = 'final class ContentHostHealth:' + source.split('final class ContentHostHealth:', 1)[1].split('/// Append-only record', 1)[0]
fixture = r'''
import Foundation
func expect(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
}
func window(_ policy: inout ContentConcurrency, _ time: inout Double,
            duration: Double = 2, network: Double = 1, processing: Double = 0.1,
            retries: Int = 0) -> String? {
    let count = policy.limit
    var result: String?
    for _ in 0..<count {
        time += duration / Double(count)
        result = policy.observe(now: time, bytes: 1_000_000, network: network,
                                processing: processing, retries: retries) ?? result
    }
    return result
}
var time = 0.0
var p = ContentConcurrency(started: time)
expect(p.limit == 8, "initial batch")
// Roundoff-safe windows above two seconds. More tasks in the same wall time
// model a network that benefits from concurrency.
expect(window(&p, &time, duration: 2.1) == "probe" && p.limit == 10, "first probe")
expect(window(&p, &time, duration: 2.1) == "probe-gain" && p.limit == 10, "keep gain")
for _ in 0..<20 { _ = window(&p, &time, duration: 2.1) }
expect(p.limit == 16 && p.peak == 16, "upper bound")
expect(window(&p, &time, duration: 2.1, retries: 1) == "retries" && p.limit == 8, "retry backoff")
expect(window(&p, &time, duration: 2.1, processing: 2) == "processing" && p.limit == 6, "processing backoff")
for _ in 0..<20 { _ = window(&p, &time, duration: 2.1, retries: 1) }
expect(p.limit == 2, "lower bound")
// A plateau at identical useful bytes/second rolls back the probe.
time = 0; p = ContentConcurrency(started: time)
_ = window(&p, &time, duration: 2.1)
expect(window(&p, &time, duration: 2.625) == "probe-no-gain" && p.limit == 8, "plateau rollback")
expect(window(&p, &time, duration: 2.1) == nil && p.limit == 8, "cooldown first")
expect(window(&p, &time, duration: 2.1) == nil && p.limit == 8, "cooldown second")
expect(window(&p, &time, duration: 2.1) == "probe", "probe resumes")
// Cached/resumed chunks, invalid clocks and partial/fast batches cannot tune.
time = 0; p = ContentConcurrency(started: time)
for _ in 0..<100 {
    expect(p.observe(now: 100, bytes: 0, network: 0, processing: 0, retries: 0) == nil, "resume ignored")
}
expect(p.observe(now: .nan, bytes: 100, network: 1, processing: 0, retries: 0) == nil, "invalid clock")
expect(p.observe(now: -1, bytes: 100, network: 1, processing: 0, retries: 0) == nil, "backwards clock")
for i in 1...8 {
    expect(p.observe(now: Double(i) / 10, bytes: 100, network: 1, processing: 0, retries: 0) == nil, "short window")
}
expect(p.limit == 8, "no premature tuning")
print("check-depot-concurrency: bounded probes, gain/plateau, retries, processing, cooldown and resume passed")
let hosts = ["https://fast", "https://slow", "https://new"]
let h = ContentHostHealth()
h.recordSuccess(hosts[0], bytes: 1_000_000, seconds: 0.1)
h.recordSuccess(hosts[1], bytes: 1_000_000, seconds: 1)
expect(h.choose(hosts, seed: 0, avoiding: []) == hosts[2], "unsampled host gets a trial")
h.recordSuccess(hosts[2], bytes: 1_000_000, seconds: 2)
var fast = 0, other = 0
for _ in 0..<64 {
    if h.choose(hosts, seed: 0, avoiding: []) == hosts[0] { fast += 1 } else { other += 1 }
}
expect(fast > 48 && other > 0, "prefer throughput while continuing exploration")
h.recordFailure(hosts[0], reason: "fixture")
for _ in 0..<24 {
    expect(h.choose(hosts, seed: 0, avoiding: []) != hosts[0], "failure takes precedence over throughput/probes")
}
h.recordSuccess(hosts[0])
for _ in 0..<24 { h.recordSuccess(hosts[0], bytes: 1_000_000, seconds: 10) }
expect(h.choose(hosts, seed: 0, avoiding: []) == hosts[1], "rates adapt to a formerly fast host slowing")
let retry = ContentHostHealth()
var tried = Set<String>()
for _ in 0..<hosts.count {
    let picked = retry.choose(hosts, seed: 0, avoiding: tried)!
    expect(!tried.contains(picked), "no repeated host before alternatives")
    tried.insert(picked)
    retry.recordFailure(picked, reason: "fixture")
}
expect(retry.choose(hosts, seed: 0, avoiding: tried) != nil, "revisit allowed after all alternatives")
expect(retry.choose([], seed: 0, avoiding: []) == nil, "empty host set")
expect(retry.order(hosts, seed: Int.min).count == hosts.count, "negative seed safe")
let invalid = ContentHostHealth()
invalid.recordSuccess(hosts[0], bytes: 100, seconds: .nan)
invalid.recordSuccess(hosts[0], bytes: 100, seconds: 0)
invalid.recordSuccess(hosts[0], bytes: -1, seconds: 1)
expect(invalid.choose(hosts, seed: 1, avoiding: []) == hosts[1], "invalid measurements ignored")
DispatchQueue.concurrentPerform(iterations: 512) { i in
    h.recordSuccess(hosts[i % hosts.count], bytes: 1_000, seconds: 0.1)
    expect(Set(h.order(hosts, seed: i)) == Set(hosts), "concurrent selection preserves host set")
}
print("check-depot-concurrency: measured host preference, exploration, failure/retry routing, rate changes and concurrent access passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    stub = 'enum SteamLog { static func event(_ message: String) {} }\n'
    path.joinpath('probe.swift').write_text('import Foundation\n' + stub + policy + health + fixture)
    compiler = shutil.which('swiftc')
    if not compiler:
        raise SystemExit('Swift compiler required; run the host regression workflow.')
    subprocess.run([compiler, str(path / 'probe.swift'), '-o', str(path / 'probe')], check=True, timeout=120)
    subprocess.run([str(path / 'probe')], check=True, timeout=30)
