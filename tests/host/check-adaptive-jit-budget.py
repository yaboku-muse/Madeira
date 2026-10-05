#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile the learned pool policy and native frontier snapshot, not replicas."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
dock = (root / 'app/Madeira/MadeiraDock.swift').read_text(encoding='utf-8')
virtual = (root / 'build/ntdll-unix/virtual_ios.c').read_text(encoding='utf-8')
model = dock[dock.index('struct AdaptiveJITRecord:'):dock.index('#if os(iOS)')]
start = virtual.index('void ios_jit_pool_usage(')
snapshot = virtual[start:virtual.index('\n}', start) + 2]
swift = 'import Foundation\n' + model + r'''
func check(_ condition: @autoclosure () -> Bool) { precondition(condition()) }
var record = AdaptiveJITRecord()
check(record.poolMB(standard: 896) == 896)
record.observe(peak: 448, capacity: 896, seconds: 179, frames: 300)
check(record.observations == 0)
record.observe(peak: 448, capacity: 896, seconds: 180, frames: 299)
check(record.observations == 0)
record.observe(peak: 448, capacity: 896, seconds: .nan, frames: 1000)
check(record.observations == 0)
record.observe(peak: 448, capacity: 896, seconds: 180, frames: 300)
check(record.observations == 1 && record.poolMB(standard: 896) == 896)
record.observe(peak: 448, capacity: 896, seconds: 300, frames: 1000)
check(record.observations == 2 && record.poolMB(standard: 896) == 704)
record.observe(peak: 480, capacity: 896, seconds: 300, frames: 1000)
check(record.peakMB == 480 && record.poolMB(standard: 896) == 768)
record.observe(peak: 100, capacity: 896, seconds: 300, frames: 1000)
check(record.peakMB == 480) // Later short/small maps never erase the peak.
let data = try JSONEncoder().encode(record)
let decoded = try JSONDecoder().decode(AdaptiveJITRecord.self, from: data)
check(decoded == record)
record.interrupted(chosen: 768, standard: 896)
check(record.blocked && record.observations == 0 && record.poolMB(standard: 896) == 896)
record.observe(peak: 100, capacity: 896, seconds: 300, frames: 1000)
check(record.poolMB(standard: 896) == 896) // An interruption blocks future shrink.
var fresh = AdaptiveJITRecord()
for _ in 0..<4 { fresh.observe(peak: 50, capacity: 896, seconds: 300, frames: 1000) }
check(fresh.observations == 2 && fresh.poolMB(standard: 896) == 512)
fresh.interrupted(chosen: 896, standard: 896)
check(!fresh.blocked && fresh.poolMB(standard: 896) == 896)
fresh.observe(peak: 850, capacity: 896, seconds: 300, frames: 1000)
check(fresh.blocked && fresh.poolMB(standard: 896) == 896)
for peak in [0, -1, 897, Int.max] {
    var invalid = AdaptiveJITRecord()
    invalid.observe(peak: peak, capacity: 896, seconds: 300, frames: 1000)
    check(invalid.observations == 0)
}
var invalid = AdaptiveJITRecord(peakMB: Int.max, observations: 20, blocked: false)
check(invalid.poolMB(standard: 896) == 896)
invalid = AdaptiveJITRecord(peakMB: 448, observations: 2, blocked: false)
check(invalid.poolMB(standard: 256) == 256)
check(invalid.poolMB(standard: Int.max) == Int.max)
check(invalid.poolMB(standard: 512) == 512)
print("PASS: learned sizing, confidence, margin, minimum, peak retention, interruption fallback and encoding")
'''
c = r'''
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
static pthread_mutex_t ios_pool_lock = PTHREAD_MUTEX_INITIALIZER;
static size_t jit_pool_offset;
static volatile size_t ios_jit_tail_reserved;
static size_t ios_jit_pool_size_global;
'''
c += snapshot + r'''
int main(void) {
  uint64_t used = 7, capacity = 7;
  ios_jit_pool_usage(&used, &capacity); assert(used == 0 && capacity == 0);
  ios_jit_pool_size_global = (size_t)896 << 20;
  jit_pool_offset = (size_t)288 << 20;
  ios_jit_tail_reserved = (size_t)160 << 20;
  ios_jit_pool_usage(&used, &capacity);
  assert(used == ((uint64_t)448 << 20) && capacity == ((uint64_t)896 << 20));
  jit_pool_offset = SIZE_MAX; ios_jit_tail_reserved = SIZE_MAX;
  ios_jit_pool_usage(&used, &capacity); assert(used == capacity);
  jit_pool_offset = 0; ios_jit_tail_reserved = SIZE_MAX;
  ios_jit_pool_usage(&used, &capacity); assert(used == capacity);
  ios_jit_pool_usage(NULL, NULL);
  ios_jit_pool_size_global = 0;
  ios_jit_pool_usage(&used, &capacity); assert(used == 0 && capacity == 0);
  assert(pthread_mutex_trylock(&ios_pool_lock) == 0); pthread_mutex_unlock(&ios_pool_lock);
  puts("PASS: conservative head/tail frontier, overlap/overflow saturation, zero pool and optional outputs");
}
'''
swiftc = shutil.which('swiftc')
compiler = shutil.which('clang') or shutil.which('cc')
if not swiftc or not compiler:
    raise SystemExit('Swift and C host compilers required; run the host regression workflow.')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('main.swift').write_text(swift)
    path.joinpath('probe.c').write_text(c)
    subprocess.run([swiftc, str(path / 'main.swift'), '-o', str(path / 'policy')], check=True)
    subprocess.run([str(path / 'policy')], check=True)
    subprocess.run([compiler, '-std=c11', '-pthread', '-fsanitize=address,undefined',
                    '-fno-omit-frame-pointer', str(path / 'probe.c'), '-o', str(path / 'snapshot')], check=True)
    subprocess.run([str(path / 'snapshot')], check=True)
