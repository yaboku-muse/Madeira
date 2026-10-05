#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Check the actual successful-creation record encoder and its publication point."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/process_ios.c').read_text(encoding='utf-8')
encoder = source[source.index('static void ios_log_process_created('):]
encoder = encoder[:encoder.index('\n}\n') + 3]
creation = source[source.index('NTSTATUS WINAPI NtCreateUserProcess('):]
creation = creation[:creation.index('\n}\n') + 3]
assert creation.count('ios_log_process_created(') == 1
assert creation.index('/* wait for the new process info to be ready */') < creation.index('if (!success)') < creation.index('ios_log_process_created(')
assert 'goto done;' in creation[creation.index('if (!success)'):creation.index('ios_log_process_created(')]
assert creation.index('ios_log_process_created(') < creation.index('/* update output attributes */')
assert 'if ((status = NtWaitForSingleObject( process_info, FALSE, NULL ))) goto done;' in creation
reply_block = creation[creation.index('SERVER_START_REQ( get_new_process_info )'):]
reply_block = reply_block[reply_block.index('\n    {'):reply_block.index('\n    SERVER_END_REQ;')]
code = r'''
#include <assert.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
typedef uint16_t WCHAR;
typedef struct { uint16_t Length, MaximumLength; WCHAR *Buffer; } UNICODE_STRING;
static char record[4096];
static int writes;
static int capture(int fd, const char *format, ...) {
    assert(fd == 2);
    va_list args; va_start(args, format);
    int n = vsnprintf(record, sizeof(record), format, args);
    va_end(args);
    assert(n > 0 && (unsigned)n < sizeof(record));
    writes++; return n;
}
#define dprintf capture
unsigned long long ios_process_generation_for_pid(unsigned pid) { return pid == 0xab ? 0x123456789abcdef0ULL : 0; }
'''
code += encoder
code += r'''
struct mock_request { unsigned info; };
struct mock_reply { int success; unsigned exit_code; };
static unsigned call_status;
static unsigned wine_server_obj_handle(int handle) { assert(handle == 7); return 7; }
static unsigned wine_server_call(struct mock_request *req) { assert(req->info == 7); return call_status; }
static void check_reply(unsigned error, int child_success, unsigned exit_code, int expected_success, unsigned expected_status) {
    unsigned status = 0;
    int success = 0, process_info = 7;
    struct mock_request request = {0}, *req = &request;
    struct mock_reply result = { child_success, exit_code }, *reply = &result;
    call_status = error;
'''
code += reply_block
code += r'''
    assert(success == expected_success && status == expected_status);
}
'''
code += r'''
int main(void) {
    check_reply(0, 1, 0, 1, 0);
    check_reply(0, 0, 0xc0000017, 0, 0xc0000017);
    /* Poisoned success fields must not defeat a failed server query. */
    check_reply(0xc0000008, 1, 0, 0, 0xc0000008);
    WCHAR path[] = {'C', ':', 0x005c, 'g', '.', 'e', 'x', 'e'};
    UNICODE_STRING image = { sizeof(path), sizeof(path), path };
    ios_log_process_created(&image, 0xab, 0xcd);
    assert(writes == 1);
    assert(!strcmp(record, "[process-created] pid=000000ab tid=000000cd status=00000000 generation=123456789abcdef0 image_utf16=0043003a005c0067002e006500780065\n"));
    WCHAR special[] = {'"', '\n', 0xe9, 0xd83d, 0xde80};
    image.Buffer = special; image.Length = sizeof(special);
    ios_log_process_created(&image, 1, 2);
    assert(writes == 2 && strstr(record, "image_utf16=0022000a00e9d83dde80\n"));
    assert(strchr(record, '\n') == record + strlen(record) - 1);
    WCHAR bounded[513];
    for (unsigned i = 0; i < 513; i++) bounded[i] = 0xffff;
    image.Buffer = bounded; image.Length = 512 * sizeof(WCHAR);
    ios_log_process_created(&image, 1, 2);
    assert(writes == 3 && strlen(strstr(record, "image_utf16=") + 12) == 2049);
    image.Length = sizeof(bounded); ios_log_process_created(&image, 1, 2);
    image.Length = 3; ios_log_process_created(&image, 1, 2);
    image.Length = 0; ios_log_process_created(&image, 1, 2);
    image.Length = sizeof(path); image.Buffer = path;
    ios_log_process_created(&image, 0, 2); ios_log_process_created(&image, 1, 0);
    image.Buffer = NULL; ios_log_process_created(&image, 1, 2);
    ios_log_process_created(NULL, 1, 2);
    assert(writes == 3);
    puts("PASS: bounded counted UTF-16 creation records; only server-confirmed success publishes");
}
'''
compiler = shutil.which('clang') or shutil.which('cc')
if not compiler:
    raise SystemExit('Host C compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory(prefix='madeira-process-record-') as directory:
    path = Path(directory)
    (path / 'probe.c').write_text(code, encoding='utf-8')
    subprocess.run([compiler, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-fno-sanitize-recover=undefined',
                    str(path / 'probe.c'), '-o', str(path / 'probe')], check=True, timeout=60)
    subprocess.run([str(path / 'probe')], check=True, timeout=30)
