#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile actual fixed-image retirement/readiness; reject another child's cleanup."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/virtual_ios.c').read_text()
def function(signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2] + '\n'
enum_start = source.index('enum ios_exewin_state\n{')
enum = source[enum_start:source.index('\n};', enum_start) + 3]
code = r'''
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
static void *ios_exe_win_img_base, *ios_exe_win_img_peb, *ios_exe_win_retiring_peb;
static void *ios_exe_win_held_base;
static size_t ios_exe_win_img_size, ios_exe_win_held_size;
static int ios_exe_win_img_dead;
static unsigned ios_exe_win_generation, ios_exe_win_retiring_generation;
static pthread_mutex_t ios_exewin_lock = PTHREAD_MUTEX_INITIALIZER;
static int ios_retire_trace_armed, ios_retire_trace_fd, ios_retire_trace_lastwr;
static int unmap_failure, hold_failure, unmaps, holds;
static void ios_retire_mark(const char *marker) { (void)marker; }
#define NtCurrentProcess() ((void *)1)
static unsigned NtUnmapViewOfSection(void *process, void *base) {
    assert(process == (void *)1 && base == (void *)0x140000000ULL);
    ++unmaps;
    return unmap_failure;
}
static void *anon_mmap_tryfixed(void *base, size_t size, int protection, int flags) {
    assert(base == (void *)0x140000000ULL && size == 0x10000);
    assert(protection == PROT_NONE && flags == MAP_NORESERVE);
    ++holds;
    if (hold_failure) { errno = EEXIST; return MAP_FAILED; }
    return base;
}
'''
code += enum + '\nstatic enum ios_exewin_state ios_exewin_st;\n'
code += function('void ios_exe_win_note_owner(')
code += function('static void ios_exe_win_note_dead_peb(')
code += function('void ios_retire_own_fixed_base_image(')
code += function('void ios_exe_win_mark_ready(')
code += r'''
static void own(void *owner, unsigned generation) {
    ios_exewin_st = IOS_EXEWIN_OWNED;
    ios_exe_win_img_base = (void *)0x140000000ULL;
    ios_exe_win_img_size = 0x10000;
    ios_exe_win_img_peb = owner;
    ios_exe_win_img_dead = 0;
    ios_exe_win_generation = generation;
    ios_exe_win_retiring_peb = NULL;
    unmap_failure = hold_failure = unmaps = holds = 0;
}
static void *wrong_cleanup(void *owner) {
    for (int i = 0; i < 1000; ++i) {
        ios_exe_win_note_owner((void *)0x140000000ULL, owner);
        ios_exe_win_note_dead_peb(owner);
        ios_exe_win_mark_ready(owner);
    }
    return NULL;
}
static void *owner_callbacks(void *owner) {
    for (int i = 0; i < 1000; ++i) {
        ios_exe_win_note_owner((void *)0x140000000ULL, owner);
        ios_exe_win_note_dead_peb(owner);
    }
    return NULL;
}
int main(void) {
    void *a = (void *)0x1000, *b = (void *)0x2000;
    unsetenv("MADEIRA_NO_IMAGE_RETIRE");
    own(a, 1);
    ios_exe_win_note_owner((void *)0x140000000ULL, b);
    ios_exe_win_note_dead_peb(b);
    assert(ios_exe_win_img_peb == a && !ios_exe_win_img_dead); /* old code stole ownership */
    pthread_t peers[8];
    for (int i = 0; i < 8; ++i) assert(!pthread_create(&peers[i], NULL, wrong_cleanup, b));
    for (int i = 0; i < 8; ++i) assert(!pthread_join(peers[i], NULL));
    assert(ios_exe_win_img_peb == a && !ios_exe_win_img_dead && ios_exewin_st == IOS_EXEWIN_OWNED);
    ios_exe_win_img_peb = NULL;
    ios_exe_win_note_owner(NULL, a);
    ios_exe_win_note_owner((void *)0x150000000ULL, a);
    assert(!ios_exe_win_img_peb);
    ios_exe_win_note_owner((void *)0x140000000ULL, a);
    assert(ios_exe_win_img_peb == a);
    for (int i = 0; i < 8; ++i) assert(!pthread_create(&peers[i], NULL, owner_callbacks, a));
    for (int i = 0; i < 8; ++i) assert(!pthread_join(peers[i], NULL));
    assert(ios_exe_win_img_dead && ios_exe_win_img_peb == a);
    ios_exe_win_note_owner((void *)0x140000000ULL, b);
    assert(ios_exe_win_img_peb == a);
    own(a, 1);
    ios_retire_own_fixed_base_image(b);
    assert(ios_exewin_st == IOS_EXEWIN_OWNED && unmaps == 0);
    ios_retire_own_fixed_base_image(a);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY && unmaps == 1 && holds == 1);
    assert(ios_exe_win_retiring_peb == a && ios_exe_win_retiring_generation == 1);
    ios_exe_win_mark_ready(b);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY); /* old code prematurely promoted */
    ios_exe_win_mark_ready(NULL);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY);
    for (int i = 0; i < 8; ++i) assert(!pthread_create(&peers[i], NULL, wrong_cleanup, b));
    for (int i = 0; i < 8; ++i) assert(!pthread_join(peers[i], NULL));
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_READY && !ios_exe_win_retiring_peb);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_READY && unmaps == 1);
    own(b, 2);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_OWNED);
    ios_retire_own_fixed_base_image(b);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY);
    ios_exe_win_mark_ready(b);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_READY);
    own(a, 3);
    unmap_failure = 1;
    ios_retire_own_fixed_base_image(a);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_OWNED && holds == 0);
    own(a, 4);
    hold_failure = 1;
    ios_retire_own_fixed_base_image(a);
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_FREE && !ios_exe_win_img_base);
    own(a, 5);
    ios_retire_own_fixed_base_image(a);
    ++ios_exe_win_generation; /* stale readiness may not publish a different generation */
    ios_exe_win_mark_ready(a);
    assert(ios_exewin_st == IOS_EXEWIN_HELD_NOT_READY);
    assert(!pthread_mutex_trylock(&ios_exewin_lock));
    pthread_mutex_unlock(&ios_exewin_lock);
    puts("PASS: actual retirement and readiness; unrelated/null/duplicate/stale-generation cleanup; 8000 concurrent wrong-owner calls; unmap and no-clobber hold failures");
}
'''
assert 'ios_exe_win_retiring_peb = dying_peb;' in source
assert 'ios_exe_win_retiring_generation = gen;' in source
with tempfile.TemporaryDirectory() as directory:
    folder = Path(directory)
    (folder / 'check.c').write_text(code)
    for label, flags in [('asan', ['-fsanitize=address,undefined', '-fno-sanitize-recover=all']),
                         ('tsan', ['-fsanitize=thread', '-no-pie'])]:
        exe = folder / label
        subprocess.run(['cc', '-std=gnu11', '-pthread', '-Wall', '-Wextra', '-Werror', '-g',
                        *flags, str(folder / 'check.c'), '-o', str(exe)], check=True)
        subprocess.run([str(exe)], check=True)
