#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile Wine's actual machine gate for the supplied x86 SDL3/x64 caller.

No Valve binaries are executed. Preserve CHPE, WOW64 and managed image routes;
fixing Steam's runtime layout must not weaken this loader check.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'wine/dlls/ntdll/loader.c').read_text(encoding='utf-8')
start = source.index('static BOOL is_valid_binary(')
gate = source[start:source.index('\n}', start) + 2]
compiler = shutil.which('cc') or shutil.which('clang')
assert compiler, 'host C compiler is required'
fixture = r'''
#include <stdint.h>
#include <assert.h>
typedef int BOOL;
typedef void *HANDLE;
#define TRUE 1
#define IMAGE_FILE_MACHINE_AMD64 0x8664
typedef struct { unsigned Machine; int ImageContainsCode; int ComPlusNativeReady; } SECTION_IMAGE_INFORMATION;
static unsigned current_machine = IMAGE_FILE_MACHINE_AMD64;
static struct { int WowTebOffset; } teb;
static int chpe, ilonly;
#define NtCurrentTeb() (&teb)
static BOOL has_chpe_metadata(HANDLE file, const SECTION_IMAGE_INFORMATION *info) { (void)file; (void)info; return chpe; }
static BOOL is_com_ilonly(HANDLE file, const SECTION_IMAGE_INFORMATION *info) { (void)file; (void)info; return ilonly; }
'''
checks = r'''
int main(void) {
    SECTION_IMAGE_INFORMATION image = {0x014c, 1, 0};
    assert(!is_valid_binary(0, &image)); /* device SDL3: x86, caller AMD64, no WOW TEB */
    image.Machine = 0x8664;
    assert(is_valid_binary(0, &image)); /* matching official AMD64 SDL3 */
    image.Machine = 0xaa64;
    assert(!is_valid_binary(0, &image)); /* ordinary ARM64 is not x64 code */
    image.Machine = 0xa641; chpe = 1;
    assert(is_valid_binary(0, &image)); /* existing ARM64EC/CHPE route */
    chpe = 0;
    assert(!is_valid_binary(0, &image));
    image.Machine = 0x014c; teb.WowTebOffset = 1;
    assert(is_valid_binary(0, &image)); /* unchanged WOW64 route */
    teb.WowTebOffset = 0; image.ImageContainsCode = 0;
    assert(is_valid_binary(0, &image)); /* resource-only image */
    image.ImageContainsCode = 1; image.ComPlusNativeReady = 1;
    assert(is_valid_binary(0, &image));
    image.ComPlusNativeReady = 0; ilonly = 1;
    assert(is_valid_binary(0, &image)); /* managed IL-only */
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='madeira-loader-machine-') as temp:
    temp = Path(temp)
    path = temp / 'gate.c'
    path.write_text(fixture + gate + checks, encoding='utf-8')
    exe = temp / 'gate'
    subprocess.run([compiler, '-std=c11', '-Wall', '-O1', '-g', '-fsanitize=address,undefined',
                    '-fno-sanitize-recover=all', str(path), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
print('PASS: actual Wine gate rejects x86 SDL3 in AMD64 caller; matching AMD64, CHPE, WOW64 and managed routes preserved')
