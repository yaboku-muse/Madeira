#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise production ring reclamation and its measured-headroom policy."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'dxmt/src/dxmt/dxmt_ring_bump_allocator.hpp').read_text(encoding='utf-8')
declaration = source[source.index('template <typename Allocator'):source.index('class GpuPrivateBufferBlockAllocator')]
implementation = source[source.index('template <typename Allocator', source.index('class HostBufferBlockAllocator')):source.rindex('} // namespace dxmt')]
budget = (root / 'dxmt/src/dxmt/dxmt_memory_budget.hpp').read_text(encoding='utf-8')
budget = budget[budget.index('namespace dxmt {'):]
queue = (root / 'dxmt/src/dxmt/dxmt_command_queue.cpp').read_text(encoding='utf-8')
initializer = (root / 'dxmt/src/dxmt/dxmt_resource_initializer.cpp').read_text(encoding='utf-8')
assert all(f'{name}.free_blocks(internal_seq, retained_blocks)' in queue
           for name in ('staging_allocator', 'copy_temp_allocator', 'argbuf_allocator'))
idle = initializer[initializer.index('  if (idle()) {'):initializer.index('  return flushInternal();')]
assert idle.index('upload_queue_event_.signaledValue()') < idle.index('gpu_command_heap_allocator.free_blocks')
assert initializer.count('gpu_command_heap_allocator.free_blocks(cached_coherent_seq_id, queryRingRetainedBlocks())') == 2

code = r'''
#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <utility>
#define WARN(...) do {} while (0)
struct Logger { static void info(const std::string &) {} };
struct madeira_ctl_args { int op; uint64_t ptr = 0, len = 0; int ret = 0; };
static int queries = 0;
static bool available = true;
static int64_t headroom = 4000;
static void MadeiraCtl(madeira_ctl_args *a) {
  assert(a->op == 7); ++queries;
  if (available) { a->ret = 1; a->len = uint64_t(headroom) << 20; }
}
namespace dxmt {
using mutex = std::mutex;
constexpr size_t kStagingBlockSize = 64, kStagingBlockLifetime = 300;
static bool reuse_enabled = false;
static bool ringOversizeReuseEnabled() { return reuse_enabled; }
static size_t align(size_t value, size_t alignment) { return (value + alignment - 1) & ~(alignment - 1); }
}
'''
code += budget + '\nnamespace dxmt {\n' + declaration + implementation + '\n}\n'
code += r'''
static unsigned live = 0, minted = 0;
struct Payload { unsigned id = ++minted; Payload() { ++live; } ~Payload() { --live; } };
struct Allocator {
  struct Block {
    std::unique_ptr<Payload> payload;
    Block() = default;
    Block(Block&&) = default;
    Block(const Block&) = delete;
  };
  Block allocate(size_t) { Block b; b.payload = std::make_unique<Payload>(); return b; }
};
using Ring = dxmt::RingBumpState<Allocator>;
int main() {
  const auto unlimited = std::numeric_limits<size_t>::max();
  assert(dxmt::ringRetainedBlocks(-1) == unlimited);
  assert(dxmt::ringRetainedBlocks(1536) == unlimited);
  assert(dxmt::ringRetainedBlocks(1535) == 2);
  assert(dxmt::ringRetainedBlocks(512) == 2);
  assert(dxmt::ringRetainedBlocks(511) == 1);
  assert(dxmt::ringRetainedBlocks(0) == 1);
  {
    Ring ring(Allocator{});
    ring.preallocate(10);
    ring.free_blocks(10); assert(live == 10); // Ordinary 300-cycle lifetime.
    ring.free_blocks(10, 2); assert(live == 2); // Prompt completion-safe trim.
    ring.free_blocks(10, 1); assert(live == 1);
    ring.free_blocks(10, 0); assert(live == 1); // A zero request still keeps latest.
    ring.free_blocks(10); assert(live == 1); // Recovery preserves reuse.
    ring.free_blocks(301); assert(live == 0); // Existing expiry still works.
  }
  {
    Ring ring(Allocator{});
    ring.allocate(1, 0, 64, 1);
    ring.allocate(2, 0, 64, 1);
    const auto newest = ring.allocate(3, 0, 32, 1).first.payload->id;
    assert(live == 3);
    ring.free_blocks(0, 1); assert(live == 3); // No unfinished block is touched.
    ring.free_blocks(1, 1); assert(live == 2);
    ring.free_blocks(2, 1); assert(live == 1);
    ring.free_blocks(3, 1); assert(live == 1);
    // The returned latest-block reference remains valid for CPU suballocation.
    assert(ring.allocate(4, 3, 16, 1).first.payload->id == newest);
    ring.seal_latest();
    assert(ring.allocate(5, 4, 32, 1).first.payload->id != newest); // Equal fence is not reuse.
    assert(live == 2);
    ring.free_blocks(4, 1); assert(live == 1);
  }
  assert(live == 0);
  {
    dxmt::reuse_enabled = true;
    Ring ring(Allocator{});
    ring.allocate(1, 0, 128, 1);
    ring.allocate(2, 0, 128, 1);
    ring.allocate(3, 0, 64, 1);
    ring.free_blocks(2, 1); assert(live == 1);
    // Trimming must repay the oversize quota, so replacement is reusable.
    ring.allocate(4, 0, 128, 1);
    assert(live == 2);
    ring.allocate(5, 4, 64, 1); // Reuse/rotate the natural block behind the oversize.
    ring.free_blocks(4); assert(live == 2); // Not wrongly classified as ad hoc.
  }
  assert(live == 0);
  assert(dxmt::queryRingRetainedBlocks() == unlimited && queries == 1);
  headroom = 1000;
  for (int i = 0; i < 100; ++i) assert(dxmt::queryRingRetainedBlocks() == unlimited);
  assert(queries == 1); // A single cached query serves all rings.
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  assert(dxmt::queryRingRetainedBlocks() == 2 && queries == 2);
  headroom = 100;
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  assert(dxmt::queryRingRetainedBlocks() == 1 && queries == 3);
  available = false;
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  assert(dxmt::queryRingRetainedBlocks() == unlimited && queries == 4);
  available = true; headroom = 4000;
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  assert(dxmt::queryRingRetainedBlocks() == unlimited && queries == 5);
  puts("PASS: pressure/recovery, cache cadence, in-flight fences, latest reference, oversize quota and lifetime");
}
'''
compiler = shutil.which('clang++') or shutil.which('c++')
if not compiler:
    raise SystemExit('Host C++ compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('probe.cpp').write_text(code)
    executable = path / 'probe'
    subprocess.run([compiler, '-std=c++20', '-pthread', '-fsanitize=address,undefined',
                    '-fno-omit-frame-pointer', str(path / 'probe.cpp'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
