#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 125hz
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile production Mach LSE decoding, alias validation and atomic updates."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/signal_arm64_ios.c').read_text(encoding='utf-8')
def function(signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2] + '\n'
production = ''.join(function(signature) for signature in [
    'static uint64_t ios_mach_lse_result(', 'static int ios_mach_emulate_lse(',
    'static int ios_mach_emulate_lse_alias('])
case4 = source[source.index('/* 4. Emulate stores to JIT-pool RX aliases'):source.index('/* FEX\'s native backpatch lock')]
assert 'ios_mach_emulate_lse_alias(insn, fault_addr, rw_addr, rx, sz, in_jit, &state, &old)' in case4
assert 'size_lg2 == 3 && ((insn >> 12) & 15) == 8' in case4  # preserve Mono capture only for 64-bit SWP
assert 'ios_mono_bridge_capture(' in case4
code = r'''
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint64_t __x[29], __fp, __lr, __sp, __pc; uint32_t __cpsr; } arm_thread_state64_t;
static uintptr_t alias_guest, alias_host;
static size_t alias_bytes;
uintptr_t ios_jit_anon_alias_lookup(uintptr_t address) {
    return address >= alias_guest && address - alias_guest < alias_bytes ? alias_host + (address - alias_guest) : 0;
}
'''
code += production
code += r'''
static uint32_t instruction(unsigned size, unsigned op, unsigned flags, unsigned rs, unsigned rt, unsigned rn) {
    return 0x38200000u | (size << 30) | (flags << 22) | (rs << 16) | (op << 12) | (rn << 5) | rt;
}
static uint64_t reg(arm_thread_state64_t *s, unsigned n) {
    return n < 29 ? s->__x[n] : n == 29 ? s->__fp : n == 30 ? s->__lr : 0;
}
static void setreg(arm_thread_state64_t *s, unsigned n, uint64_t value) {
    if (n < 29) s->__x[n] = value; else if (n == 29) s->__fp = value; else if (n == 30) s->__lr = value;
}
static uint64_t oracle(unsigned op, unsigned bytes, uint64_t a, uint64_t b) {
    uint64_t mask = bytes == 8 ? UINT64_MAX : (1ULL << (8 * bytes)) - 1;
    a &= mask; b &= mask;
    // independent signed interpretation by sign extension, without signed overflow
    int64_t sa = bytes == 8 ? (int64_t)a : (int64_t)(a << (64 - 8 * bytes)) >> (64 - 8 * bytes);
    int64_t sb = bytes == 8 ? (int64_t)b : (int64_t)(b << (64 - 8 * bytes)) >> (64 - 8 * bytes);
    switch(op) {
    case 0: return (a + b) & mask; case 1: return a & ~b; case 2: return a ^ b; case 3: return a | b;
    case 4: return sa > sb ? a : b; case 5: return sa < sb ? a : b;
    case 6: return a > b ? a : b; case 7: return a < b ? a : b; default: return b;
    }
}
static uint64_t counter, returned_sum;
static void *add_peer(void *unused) {
    (void)unused;
    uint64_t old, sum = 0;
    for (unsigned i = 0; i < 20000; i++) {
        assert(ios_mach_emulate_lse(0xf8e60020, (uintptr_t)&counter, 1, &old));
        sum += old;
    }
    __atomic_fetch_add(&returned_sum, sum, __ATOMIC_SEQ_CST);
    return NULL;
}
int main(void) {
    _Alignas(8) uint8_t memory[32];
    const uint64_t values[] = {0, 1, UINT64_MAX, 0x80, 0x8000, 0x80000000ULL, 0x8000000000000000ULL, 0x123456789abcdef0ULL};
    for (unsigned size = 0; size < 4; size++) for (unsigned op = 0; op <= 8; op++)
    for (unsigned flags = 0; flags < 4; flags++) for (unsigned ai = 0; ai < 8; ai++) for (unsigned bi = 0; bi < 8; bi++) {
        unsigned bytes = 1u << size;
        uint64_t old = 0, now = 0;
        memset(memory, 0x5a, sizeof(memory)); memcpy(memory + 8, &values[ai], bytes);
        assert(ios_mach_emulate_lse(instruction(size, op, flags, 6, 0, 1), (uintptr_t)(memory + 8), values[bi], &old));
        memcpy(&now, memory + 8, bytes);
        uint64_t before = 0; memcpy(&before, &values[ai], bytes);
        assert(old == before && now == oracle(op, bytes, values[ai], values[bi]));
        for (unsigned k = 0; k < 32; k++) if (k < 8 || k >= 8 + bytes) assert(memory[k] == 0x5a);
    }
    alias_guest = 0x70000000; alias_host = (uintptr_t)memory; alias_bytes = 8;
    arm_thread_state64_t s = {0}; s.__x[1] = alias_guest; s.__x[6] = 0xffffffff00000003ULL;
    s.__sp = 0xfeed; s.__cpsr = 0x1234; s.__pc = 0x9876;
    uint32_t word = 7; memcpy(memory, &word, 4); uint64_t old;
    assert(instruction(2, 0, 3, 6, 0, 1) == 0xb8e60020); // actual HotSpot report
    assert(ios_mach_emulate_lse_alias(0xb8e60020, alias_guest, alias_host, 0, 0, 0, &s, &old));
    memcpy(&word, memory, 4); assert(word == 10 && old == 7 && s.__x[0] == 7);
    assert(s.__sp == 0xfeed && s.__pc == 0x9876 && s.__cpsr == 0x1234 && s.__x[6] == 0xffffffff00000003ULL);
    for (unsigned rs = 0; rs < 32; rs++) for (unsigned rt = 0; rt < 32; rt++) {
        s = (arm_thread_state64_t){0}; s.__sp = 0xfeed;
        setreg(&s, rs, 3); word = 7; memcpy(memory, &word, 4);
        // Use SP as base for every source/destination combination.
        s.__sp = alias_guest;
        assert(ios_mach_emulate_lse_alias(instruction(2, 0, 3, rs, rt, 31), alias_guest, alias_host,
                                          alias_guest, 8, 1, &s, &old));
        memcpy(&word, memory, 4); assert(word == (rs == 31 ? 7 : 10) && old == 7);
        assert(s.__sp == alias_guest && reg(&s, rt) == (rt == 31 ? 0 : 7));
    }
    uint8_t snapshot[32]; memcpy(snapshot, memory, sizeof(memory));
    s = (arm_thread_state64_t){0}; s.__x[1] = alias_guest;
    arm_thread_state64_t saved; memcpy(&saved, &s, sizeof(s));
    alias_bytes = 3; // first byte resolves but the complete 32-bit operand does not
    assert(!ios_mach_emulate_lse_alias(0xb8e60020, alias_guest, alias_host, 0, 0, 0, &s, &old));
    alias_bytes = 8;
    assert(!ios_mach_emulate_lse_alias(0xb8e60020, alias_guest, alias_host, alias_guest, 3, 1, &s, &old));
    assert(!ios_mach_emulate_lse_alias(0xb8e60020, alias_guest, alias_host + 1, alias_guest, 8, 1, &s, &old));
    assert(!ios_mach_emulate_lse_alias(0xb8e60020, alias_guest + 1, alias_host, alias_guest, 8, 1, &s, &old));
    assert(!ios_mach_emulate_lse_alias(0xb8e60020, UINTPTR_MAX, alias_host, 0, 0, 0, &s, &old));
    for (unsigned op = 9; op < 16; op++) assert(!ios_mach_emulate_lse(instruction(2, op, 3, 6, 0, 1), alias_host, 1, &old));
    assert(!ios_mach_emulate_lse(0xd503201f, alias_host, 1, &old)); // NOP
    assert(!ios_mach_emulate_lse(0x880cfd0b, alias_host, 1, &old)); // STLXR is a separate reservation protocol
    assert(!ios_mach_emulate_lse(0xa9882149, alias_host, 1, &old)); // pre-index STP is separate
    assert(!ios_mach_emulate_lse(0xc8e0fc00, alias_host, 1, &old)); // CAS stays separate
    assert(!ios_mach_emulate_lse(0xb8e60020, 0, 1, &old));
    assert(!ios_mach_emulate_lse(0xb8e60020, alias_host, 1, NULL));
    assert(!memcmp(memory, snapshot, sizeof(memory)) && !memcmp(&s, &saved, sizeof(s)));
    pthread_t peers[4];
    for (unsigned i = 0; i < 4; i++) assert(!pthread_create(&peers[i], NULL, add_peer, NULL));
    for (unsigned i = 0; i < 4; i++) assert(!pthread_join(peers[i], NULL));
    assert(counter == 80000 && returned_sum == 80000ULL * 79999 / 2);
    puts("PASS: actual Mach LSE opcode, all widths/operations/order flags, zero/FP/LR registers, full alias bounds, unchanged refusal, and 80000 concurrent atomic increments");
}
'''
compiler = shutil.which('cc') or shutil.which('clang')
assert compiler, 'host C compiler required'
with tempfile.TemporaryDirectory(prefix='madeira-mach-lse-') as directory:
    path = Path(directory)
    (path / 'probe.c').write_text(code, encoding='utf-8')
    for sanitizer in ['address,undefined', 'thread']:
        exe = path / sanitizer.replace(',', '-')
        subprocess.run([compiler, '-std=gnu11', '-O1', '-Wall', '-Wextra', '-Werror', '-pthread',
                        '-fsanitize=' + sanitizer, '-fno-omit-frame-pointer', str(path / 'probe.c'), '-o', str(exe)], check=True)
        subprocess.run([str(exe)], check=True, timeout=60,
                       env=dict(os.environ, ASAN_OPTIONS='detect_leaks=1', TSAN_OPTIONS='halt_on_error=1'))
