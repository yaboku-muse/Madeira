#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise the actual iOS child spawn path with allocation/FD/thread failures."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/process_ios.c').read_text(encoding='utf-8')
spawn = source[source.index('static NTSTATUS spawn_process('):]
spawn = spawn[:spawn.index('\n#else')]
spawn += '\n#endif\n}\n'
code = r'''
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
typedef uint32_t NTSTATUS;
typedef struct { int unused; } UNICODE_STRING;
typedef struct { UNICODE_STRING CommandLine, ImagePathName; } RTL_USER_PROCESS_PARAMETERS;
struct pe_image_info { int machine; };
struct ios_child_args { int socketfd, unixdir, argc, slot; char **argv; struct pe_image_info pe_info; };
#define WINE_IOS 1
#define ERR(...) do {} while (0)
#define STATUS_SUCCESS 0
#define STATUS_NO_MEMORY 0xc0000017u
#define STATUS_TOO_MANY_OPENED_FILES 0xc000011fu
#define STATUS_INVALID_HANDLE 0xc0000008u
static int fail_argv, fail_alloc, fail_dup, fail_thread, dup_calls, created, detached;
static int copies[2], copy_count, slots, released;
static struct ios_child_args *owned;
static NTSTATUS errno_to_status(int error) {
    assert(error == EMFILE || error == EBADF);
    return error == EMFILE ? STATUS_TOO_MANY_OPENED_FILES : STATUS_INVALID_HANDLE;
}
static char **build_argv(const UNICODE_STRING *line, int reserved) {
    assert(line && reserved == 2);
    if (fail_argv) return NULL;
    return calloc(3, sizeof(char *));
}
static void *probe_calloc(size_t n, size_t size) {
    return fail_alloc ? NULL : calloc(n, size);
}
static int probe_dup(int fd) {
    if (++dup_calls == fail_dup) { errno = fail_dup == 1 ? EMFILE : EBADF; return -1; }
    int copy = dup(fd);
    assert(copy >= 0 && copy_count < 2);
    copies[copy_count++] = copy;
    return copy;
}
static int ios_child_slot_take(const UNICODE_STRING *image) { assert(image); slots++; return 7; }
static void ios_child_slot_release(int slot) { if (slot == -1) return; assert(slot == 7); released++; }
static void *ios_child_thread_entry(void *args) { (void)args; abort(); }
static int probe_create(pthread_t *thread, const pthread_attr_t *attr, void *(*entry)(void *), void *args) {
    assert(thread && !attr && entry == ios_child_thread_entry);
    created++;
    if (fail_thread) return EAGAIN;
    *thread = pthread_self();
    owned = args;
    return 0;
}
static int probe_detach(pthread_t thread) { (void)thread; detached++; return 0; }
#define calloc probe_calloc
#define dup probe_dup
#define pthread_create probe_create
#define pthread_detach probe_detach
'''
code += spawn
code += r'''
#undef calloc
#undef dup
#undef pthread_create
#undef pthread_detach
static void reset(void) {
    fail_argv = fail_alloc = fail_dup = fail_thread = dup_calls = created = detached = 0;
    copy_count = slots = released = 0;
    owned = NULL;
}
static void descriptors_clean(int socketfd, int dirfd) {
    assert(fcntl(socketfd, F_GETFD) >= 0 && fcntl(dirfd, F_GETFD) >= 0);
    for (int i = 0; i < copy_count; i++) {
        errno = 0;
        assert(fcntl(copies[i], F_GETFD) == -1 && errno == EBADF);
    }
}
static void failed_clean(int socketfd, int dirfd) {
    assert(!owned && detached == 0 && slots == released);
    descriptors_clean(socketfd, dirfd);
}
int main(void) {
    int pipefd[2]; assert(pipe(pipefd) == 0);
    int dirfd = open(".", O_RDONLY); assert(dirfd >= 0);
    RTL_USER_PROCESS_PARAMETERS params = {0};
    struct pe_image_info image = {8664};
    reset(); fail_argv = 1;
    assert(spawn_process(&params, pipefd[0], dirfd, NULL, &image) == STATUS_NO_MEMORY);
    assert(!dup_calls && !created); failed_clean(pipefd[0], dirfd);
    reset(); fail_alloc = 1;
    assert(spawn_process(&params, pipefd[0], dirfd, NULL, &image) == STATUS_NO_MEMORY);
    assert(!dup_calls && !created); failed_clean(pipefd[0], dirfd);
    reset(); fail_dup = 1;
    assert(spawn_process(&params, pipefd[0], dirfd, NULL, &image) == STATUS_TOO_MANY_OPENED_FILES);
    assert(dup_calls == 1 && !created && !slots); failed_clean(pipefd[0], dirfd);
    reset(); fail_dup = 2;
    assert(spawn_process(&params, pipefd[0], dirfd, NULL, &image) == STATUS_INVALID_HANDLE);
    assert(copy_count == 1 && !created && !slots); failed_clean(pipefd[0], dirfd);
    for (int i = 0; i < 1000; i++) {
        reset(); fail_thread = 1;
        assert(spawn_process(&params, pipefd[0], dirfd, NULL, &image) == STATUS_NO_MEMORY);
        assert(created == 1 && copy_count == 2); failed_clean(pipefd[0], dirfd);
    }
    reset(); fail_thread = 1;
    assert(spawn_process(&params, pipefd[0], -1, NULL, &image) == STATUS_NO_MEMORY);
    assert(copy_count == 1); failed_clean(pipefd[0], dirfd);
    for (int use_dir = 0; use_dir <= 1; use_dir++) {
        reset();
        assert(spawn_process(&params, pipefd[0], use_dir ? dirfd : -1, NULL, &image) == STATUS_SUCCESS);
        assert(owned && created == 1 && detached == 1 && slots == 1 && !released);
        assert(owned->argc == 2 && owned->pe_info.machine == image.machine);
        assert(fcntl(owned->socketfd, F_GETFD) >= 0 && owned->socketfd != pipefd[0]);
        if (use_dir) assert(fcntl(owned->unixdir, F_GETFD) >= 0 && owned->unixdir != dirfd);
        else assert(owned->unixdir == -1);
        close(owned->socketfd);
        if (owned->unixdir != -1) close(owned->unixdir);
        ios_child_slot_release(owned->slot); free(owned->argv); free(owned); owned = NULL;
        assert(slots == released);
        descriptors_clean(pipefd[0], dirfd);
    }
    close(pipefd[0]); close(pipefd[1]); close(dirfd);
    puts("PASS: child spawn failures release duplicates/slots; parent descriptors and success ownership preserved");
}
'''
compiler = shutil.which('clang') or shutil.which('cc')
if not compiler:
    raise SystemExit('Host C compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory(prefix='madeira-child-spawn-') as directory:
    path = Path(directory)
    (path / 'probe.c').write_text(code, encoding='utf-8')
    subprocess.run([compiler, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-fno-sanitize-recover=undefined',
                    str(path / 'probe.c'), '-o', str(path / 'probe')], check=True, timeout=60)
    subprocess.run([str(path / 'probe')], check=True, timeout=30,
                   env=dict(os.environ, ASAN_OPTIONS='detect_leaks=1'))
