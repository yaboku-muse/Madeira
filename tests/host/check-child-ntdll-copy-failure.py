#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Run the production child-copy boot block with injected allocation failure."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/loader_ios.c').read_text()
macro = source.split('#define CHILD_STAGE(s)', 1)[1].split('    CHILD_STAGE( "entry" );', 1)[0]
macro = '#define CHILD_STAGE(s)' + macro
block = source.split('/* S1: per-child ntdll copy.', 1)[1]
block = block[block.index('\n        {'):block.index('\n\n        /* Keep peb = child_peb')]
assert block.rstrip().endswith('}')
code = r'''
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
typedef uintptr_t UINT_PTR;
#define ERR(...) do {} while (0)
static const char *ios_child_boot_stage;
static int argc = 2;
static char *argv[] = {"wine", "fixture.exe"};
static void *child_peb = (void *)0x2000;
static void *pLdrInitializeThunk = (void *)0x1000;
static int fail_copy, copies, translates, syncs, patches, entered, unlocks, ec;
static uint64_t syscall_slot, unix_slot, handle_slot;
static void *syscall_pe, *unix_pe;
static UINT_PTR handle_pe;
static void **ios_ntdll_syscall_dispatcher_ptr = &syscall_pe;
static void **ios_ntdll_unix_call_dispatcher_ptr = &unix_pe;
static UINT_PTR *ios_ntdll_unixlib_handle_ptr = &handle_pe;
static void *unix_call_funcs = (void *)0x3000;
static void __wine_syscall_dispatcher(void) {}
static void ios_child_boot_unlock(void) { unlocks++; }
int ios_jit_copy_module_for_child(void *module, void *owner) {
    assert(module == pLdrInitializeThunk && owner == child_peb);
    copies++; return fail_copy;
}
void *ios_jit_translate_addr(void *address) {
    translates++;
    if (address == ios_ntdll_syscall_dispatcher_ptr) return &syscall_slot;
    if (address == ios_ntdll_unix_call_dispatcher_ptr) return &unix_slot;
    if (address == ios_ntdll_unixlib_handle_ptr) return &handle_slot;
    return (void *)0x5000;
}
void ios_jit_sync_write(void *address, size_t size) {
    syncs++; assert(size == sizeof(void *));
    if (address == ios_ntdll_syscall_dispatcher_ptr) syscall_slot = (uintptr_t)syscall_pe;
    else { assert(address == ios_ntdll_unixlib_handle_ptr); handle_slot = handle_pe; }
}
static int is_arm64ec(void) { return ec; }
int ios_patch_rtl_pc_to_file_header_current(const void *address) {
    assert(address == pLdrInitializeThunk); patches++; return 0;
}
'''
code += macro + '\nstatic void boot_copy(void) {\n' + block + '\nentered++;\n}\n'
code += r'''
int main(void) {
    fail_copy = 1; boot_copy();
    assert(copies == 1 && unlocks == 1 && entered == 0);
    assert(translates == 0 && syncs == 0 && patches == 0);
    assert(syscall_slot == 0 && handle_slot == 0);
    fail_copy = 0; ec = 1; boot_copy();
    assert(copies == 2 && unlocks == 1 && entered == 1);
    assert(translates == 4 && syncs == 2 && patches == 1);
    assert(syscall_slot == (uintptr_t)__wine_syscall_dispatcher);
    assert(handle_slot == (uintptr_t)unix_call_funcs);
    ec = 0; boot_copy();
    assert(copies == 3 && entered == 2 && unlocks == 1);
    assert(syncs == 2 && patches == 1);
    puts("check-child-ntdll-copy-failure: failed child returns before dispatch/state writes; successful EC/native paths retained");
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('probe.c').write_text(code)
    compiler = shutil.which('clang') or shutil.which('cc')
    if not compiler:
        raise SystemExit('Host C compiler required; run the host regression workflow.')
    subprocess.run([compiler, '-std=gnu11', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                    str(path / 'probe.c'), '-o', str(path / 'probe')], check=True, timeout=60)
    subprocess.run([str(path / 'probe')], check=True, timeout=30)
