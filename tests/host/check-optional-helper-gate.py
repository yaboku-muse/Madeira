#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise the actual optional-helper gate with counted UTF-16 paths."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/process_ios.c').read_text(encoding='utf-8')
start = source.index('static const char *ios_optional_helper_gate(')
function = source[start:source.index('\n}', start) + 2]
assert 'const char *blocked = ios_optional_helper_gate( params->ImagePathName.Buffer,' in source
fixture = r'''
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>
typedef uint16_t WCHAR;
#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))
'''
checks = r'''
static int gated(const char *path) {
    WCHAR image[256];
    unsigned i, n = strlen(path);
    assert(n < ARRAY_SIZE(image));
    for (i = 0; i < n; i++) image[i] = (unsigned char)path[i];
    return ios_optional_helper_gate(image, n) != NULL;
}
int main(void) {
    const char *const helpers[] = {
        "steamerrorreporter.exe", "steamerrorreporter64.exe", "gldriverquery.exe", "gldriverquery64.exe",
        "vulkandriverquery.exe", "vulkandriverquery64.exe", "steamsysinfo.exe", "steamsysinfo64.exe",
        "hardwareupdater.exe", "unitycrashhandler64.exe"
    };
    char path[256];
    unsigned i, j;
    for (i = 0; i < ARRAY_SIZE(helpers); i++) {
        assert(gated(helpers[i]));
        snprintf(path, sizeof(path), "C:\\Steam\\bin\\%s", helpers[i]);
        assert(gated(path));
        for (j = 0; path[j]; j++) if (path[j] >= 'a' && path[j] <= 'z') path[j] -= 'a' - 'A';
        assert(gated(path));
        snprintf(path, sizeof(path), "C:/Games/%s/game.exe", helpers[i]);
        assert(!gated(path));
        snprintf(path, sizeof(path), "C:/Games/my_%s", helpers[i]);
        assert(!gated(path));
        snprintf(path, sizeof(path), "C:/Games/%s.backup", helpers[i]);
        assert(!gated(path));
    }
    assert(gated("C:steamerrorreporter64.exe"));
    assert(!gated("C:\\Games\\hardwareupdater simulator\\play.exe"));
    assert(!gated("C:\\Games\\UnityCrashHandler64 Edition\\play.exe"));
    assert(!gated("C:\\Games\\steamsysinfo-game.exe"));
    assert(!gated("C:\\Games\\crashpad_handler.exe")); /* no blanket child gate */
    assert(!gated(""));
    assert(!ios_optional_helper_gate(NULL, 0));
    { const WCHAR short_name[] = {'g','l'}; assert(!ios_optional_helper_gate(short_name, 2)); }
    { const WCHAR directory[] = {'C',':','\\'}; assert(!ios_optional_helper_gate(directory, 3)); }
    return 0;
}
'''
compiler = shutil.which('cc') or shutil.which('clang')
assert compiler, 'host C compiler is required'
with tempfile.TemporaryDirectory(prefix='madeira-helper-gate-') as temp:
    temp = Path(temp)
    path = temp / 'gate.c'
    path.write_text(fixture + function + checks, encoding='utf-8')
    exe = temp / 'gate'
    subprocess.run([compiler, '-std=c11', '-Wall', '-O1', '-g', '-fsanitize=address,undefined',
                    '-fno-sanitize-recover=all', str(path), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
print('PASS: exact counted helper basenames; case/path variants; no directory, prefix or suffix false positives; child containment unchanged')
