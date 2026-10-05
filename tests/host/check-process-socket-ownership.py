#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Run production socket ownership/exit code with real descriptors and concurrent owners."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/ntdll-unix/server_ios.c').read_text(encoding='utf-8')
registry = source[source.index('#define IOS_PROC_SOCKET_BUCKETS'):source.index('#define IOS_FDT_MAX')]
registration = source[source.index('static BOOL ios_register_proc_socket('):]
registration = registration[:registration.index('\n}\n') + 3]
teardown = source[source.index('void process_exit_wrapper( int status )'):]
teardown = teardown[:teardown.index('\n}\n') + 3]
initial = source[source.index('size_t server_init_process(void)'):source.index('size_t server_init_process_child(')]
assert 'ios_session_peb = ios_jit_current_peb();' in initial
child = source[source.index('size_t server_init_process_child('):]
assert 'if (!ios_register_proc_socket(' in child and 'close( child_fd_socket );' in child
assert child.index('if (ret) server_protocol_error( "init_first_thread (child)') < child.index('ios_bind_proc_pid( pid );')
assert teardown.index('close( owned_fd );') < teardown.index('ios_log_process_exit( entry, status );')
assert '-include "$BUILD_DIR/shims/wine_ios_exit.h"' in (root / 'build/ntdll-unix/build.sh').read_text()
thread_source = (root / 'build/ntdll-unix/thread_ios.c').read_text()
worker = thread_source[thread_source.index('static void start_thread( TEB *teb )'):]
assert worker.index('ios_bind_proc_socket_thread();') < worker.index('server_init_thread(')
startup_start = thread_source.index('struct ios_thread_start_args\n{')
startup = thread_source[startup_start:thread_source.index('static SIZE_T get_machine_context_size', startup_start)]
assert startup.index('args->process_record = ios_capture_proc_socket_thread();') < startup.index('pthread_create(')
assert 'ios_create_native_thread( &pthread_id, &pthread_attr, teb )' in thread_source
code = r'''
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
typedef int BOOL;
#define TRUE 1
#define FALSE 0
#define WINE_IOS 1
#define FDT_MASTER 1
static int fd_socket = -1;
static BOOL process_exiting;
static _Thread_local void *owner;
void *ios_jit_current_peb(void) { return owner; }
static int fail_alloc;
static void *probe_calloc(size_t n, size_t size) { return fail_alloc ? NULL : calloc(n, size); }
static atomic_uint reclaims, retires, cache_releases, subfloor_releases, wow_releases, ready, exits, notes;
static atomic_uint exit_records;
static char last_exit_record[256];
static int capture_exit(int fd, const char *format, ...) {
    assert(fd == 2);
    va_list args; va_start(args, format);
    int size = vsnprintf(last_exit_record, sizeof(last_exit_record), format, args);
    va_end(args);
    assert(size > 0 && (unsigned)size < sizeof(last_exit_record));
    atomic_fetch_add(&exit_records, 1); return size;
}
#define dprintf capture_exit
atomic_uint parent_exits;
atomic_uint lifetime_callbacks;
static void wine_log_write(const char *format, ...) { (void)format; }
static void ios_fdt_reg(int fd, int kind, void *peb) { assert(fd >= 0 && kind == FDT_MASTER && peb); }
static void ios_fdt_note_close(int fd, const char *reason, void *peb) {
    assert(fd >= 0 && reason && peb); atomic_fetch_add(&notes, 1);
}
void ios_jit_reclaim_process(void *peb) { assert(peb == owner); atomic_fetch_add(&reclaims, 1); }
void ios_retire_own_fixed_base_image(void *peb) { assert(peb == owner); atomic_fetch_add(&retires, 1); }
void ios_fd_cache_release(void *peb) { assert(peb == owner); atomic_fetch_add(&cache_releases, 1); }
void ios_subfloor_release_owner(void *peb) { assert(peb == owner); atomic_fetch_add(&subfloor_releases, 1); }
void ios_wow_window_release(void *peb) { assert(peb == owner); atomic_fetch_add(&wow_releases, 1); }
void ios_exe_win_mark_ready(void *peb) { assert(peb == owner); atomic_fetch_add(&ready, 1); }
static void probe_exit(int status) { assert(status == 0); atomic_fetch_add(&exits, 1); }
#define calloc probe_calloc
#define exit probe_exit
'''
code += registry + registration + teardown
code += r'''
#undef calloc
#undef exit
typedef struct { void *owner; } TEB;
static int startup_fd, started_count, fail_start_alloc, fail_thread_create;
static void *queued_start_args;
static void *(*queued_start)(void *);
static void start_thread(TEB *teb) {
    owner = teb->owner;
    ++started_count;
    startup_fd = ios_current_fd_socket();
}
static void *probe_malloc(size_t size) { return fail_start_alloc ? NULL : malloc(size); }
static int probe_pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                                void *(*entry)(void *), void *arg) {
    (void)attr;
    if (fail_thread_create) return EAGAIN;
    *thread = pthread_self(); queued_start = entry; queued_start_args = arg;
    return 0; /* deterministic scheduling delay before executing the actual entry */
}
#define malloc probe_malloc
#define pthread_create probe_pthread_create
'''
code += startup
code += r'''
#undef malloc
#undef pthread_create
static void parent_alive(void) { assert(fcntl(fd_socket, F_GETFD) >= 0); }
static void closed(int fd) { errno = 0; assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF); }
static void *exit_peer(void *peb) { owner = peb; process_exit_wrapper(0); return NULL; }
static int successor_fd;
static void *register_successor(void *peb) {
    owner = peb;
    assert(ios_register_proc_socket(owner, successor_fd));
    assert(ios_current_fd_socket() == successor_fd);
    return NULL;
}
static void *many_owners(void *lane_ptr) {
    uintptr_t lane = (uintptr_t)lane_ptr;
    for (unsigned i = 0; i < 200; i++) {
        owner = (void *)(0x1000000 + lane * 0x1000000 + i * 0x4000);
        int fd = dup(fd_socket); assert(fd >= 0);
        assert(ios_register_proc_socket(owner, fd));
        assert(ios_current_fd_socket() == fd);
        process_exit_wrapper(0);
        assert(ios_current_fd_socket() == -1);
        process_exit_wrapper(0); /* retained identity: never closes parent */
    }
    return NULL;
}
int main(void) {
    int pipefd[2]; assert(pipe(pipefd) == 0); fd_socket = pipefd[0];
    ios_session_peb = (void *)0x1000; owner = ios_session_peb;
    assert(ios_current_fd_socket() == fd_socket && ios_process_exiting_ptr() == &process_exiting);
    owner = (void *)0x2000;
    assert(ios_current_fd_socket() == -1 && ios_process_exiting_ptr() != &process_exiting);
    process_exit_wrapper(0); parent_alive(); assert(parent_exits == 0 && reclaims == 0);
    int child_fd = dup(fd_socket); assert(child_fd >= 0);
    fail_alloc = 1; assert(!ios_register_proc_socket(owner, child_fd)); fail_alloc = 0;
    assert(ios_current_fd_socket() == -1); close(child_fd); parent_alive();
    assert(!ios_register_proc_socket(NULL, fd_socket) && !ios_register_proc_socket(owner, -1));
    child_fd = dup(fd_socket); assert(ios_register_proc_socket(owner, child_fd));
    ios_bind_proc_pid(0xab);
    unsigned long long original_generation = ios_process_generation_for_pid(0xab);
    assert(original_generation && !ios_process_generation_for_pid(0) && !ios_process_generation_for_pid(0xcd));
    BOOL *old_flag = ios_process_exiting_ptr(); *old_flag = TRUE;
    pthread_t peers[8]; unsigned before = reclaims;
    for (unsigned i = 0; i < 8; i++) assert(pthread_create(&peers[i], NULL, exit_peer, owner) == 0);
    for (unsigned i = 0; i < 8; i++) pthread_join(peers[i], NULL);
    assert(exit_records == 1 && strstr(last_exit_record, "pid=000000ab") &&
           strstr(last_exit_record, "status_kind=unix status=00000000\n"));
    assert(ios_process_generation_for_pid(0xab) == original_generation); /* fast exit before parent creation log */
    assert(reclaims == before + 1 && retires == reclaims && cache_releases == reclaims &&
           subfloor_releases == reclaims && wow_releases == reclaims && ready == reclaims && notes == reclaims);
    closed(child_fd); parent_alive(); assert(ios_current_fd_socket() == -1 && ios_process_exiting_ptr() == old_flag);
    /* Reused FD number belongs to a different live child, not the retired one. */
    void *retired_owner = owner;
    owner = (void *)0x3000; int new_fd = dup(fd_socket); assert(new_fd >= 0);
    assert(ios_register_proc_socket(owner, new_fd));
    owner = retired_owner; ios_thread_proc_socket = NULL; /* fixture switches native process context */
    process_exit_wrapper(0); assert(fcntl(new_fd, F_GETFD) >= 0); parent_alive();
    /* Latest registration at a reused PEB address wins; prior flag pointers stay valid. */
    child_fd = dup(fd_socket); assert(ios_register_proc_socket(owner, child_fd));
    assert(ios_current_fd_socket() == child_fd && ios_process_exiting_ptr() != old_flag && *old_flag == TRUE);
    ios_bind_proc_pid(0xab);
    assert(ios_process_generation_for_pid(0xab) > original_generation);
    ios_note_process_exit_status(0xc0000005);
    process_exit_wrapper(0);
    assert(exit_records == 2 && strstr(last_exit_record, "status_kind=windows status=c0000005\n"));
    /* An old peer has captured the retired generation. Register a successor
     * at exactly the same PEB address on a different native thread. */
    BOOL *retired_flag = ios_process_exiting_ptr();
    successor_fd = dup(fd_socket); assert(successor_fd >= 0);
    assert(pthread_create(&peers[0], NULL, register_successor, owner) == 0);
    assert(pthread_join(peers[0], NULL) == 0);
    assert(ios_current_fd_socket() == -1 && ios_process_exiting_ptr() == retired_flag);
    unsigned after_retired = reclaims;
    process_exit_wrapper(0);
    assert(reclaims == after_retired && fcntl(successor_fd, F_GETFD) >= 0);
    assert(pthread_create(&peers[0], NULL, exit_peer, owner) == 0);
    assert(pthread_join(peers[0], NULL) == 0);
    closed(successor_fd); assert(reclaims == after_retired + 1); parent_alive();
    /* Capture the creator record before pthread scheduling. A successor may
     * register at the same PEB before the actual worker entry gets a timeslice. */
    TEB delayed_teb = { owner };
    fail_start_alloc = 1;
    assert(ios_create_native_thread(&peers[0], NULL, &delayed_teb) == ENOMEM);
    fail_start_alloc = 0; fail_thread_create = 1;
    assert(ios_create_native_thread(&peers[0], NULL, &delayed_teb) == EAGAIN);
    fail_thread_create = 0;
    assert(ios_create_native_thread(&peers[0], NULL, &delayed_teb) == 0);
    successor_fd = dup(fd_socket); assert(successor_fd >= 0);
    assert(pthread_create(&peers[0], NULL, register_successor, owner) == 0);
    assert(pthread_join(peers[0], NULL) == 0);
    assert(pthread_create(&peers[0], NULL, queued_start, queued_start_args) == 0);
    assert(pthread_join(peers[0], NULL) == 0);
    assert(started_count == 1 && startup_fd == -1 && fcntl(successor_fd, F_GETFD) >= 0);
    assert(pthread_create(&peers[0], NULL, exit_peer, owner) == 0);
    assert(pthread_join(peers[0], NULL) == 0);
    closed(successor_fd); parent_alive();
    owner = (void *)0x3000; ios_thread_proc_socket = NULL; process_exit_wrapper(0);
    before = reclaims;
    for (uintptr_t i = 0; i < 4; i++) assert(pthread_create(&peers[i], NULL, many_owners, (void *)i) == 0);
    for (unsigned i = 0; i < 4; i++) pthread_join(peers[i], NULL);
    assert(reclaims == before + 800 && parent_exits == 0); parent_alive();
    owner = NULL; ios_thread_proc_socket = NULL;
    assert(ios_current_fd_socket() == fd_socket); /* initial/foreign bootstrap */
    owner = ios_session_peb; process_exit_wrapper(0); assert(parent_exits == 1); closed(fd_socket);
    assert(lifetime_callbacks == exit_records);
    close(pipefd[1]);
    puts("PASS: >64 child owners, stable per-thread generation after PEB reuse, retired identity, allocation failure, duplicate/concurrent teardown and parent isolation");
}
'''
compiler = shutil.which('cc') or shutil.which('clang')
if not compiler:
    raise SystemExit('Host C compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory(prefix='madeira-socket-owners-') as directory:
    path = Path(directory)
    (path / 'probe.c').write_text(code, encoding='utf-8')
    (path / 'hook.c').write_text('''#include <assert.h>
#include <stdatomic.h>
extern atomic_uint parent_exits;
extern atomic_uint lifetime_callbacks;
void wine_ui_log(const char *message) { assert(message && message[0] == '['); atomic_fetch_add(&lifetime_callbacks, 1); }
void wine_launched_process_did_exit(int status) { assert(status == 0); atomic_fetch_add(&parent_exits, 1); }
''', encoding='utf-8')
    for sanitizer in ['address,undefined', 'thread']:
        exe = path / sanitizer.replace(',', '-')
        subprocess.run([compiler, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        '-fsanitize=' + sanitizer, '-fno-omit-frame-pointer',
                        str(path / 'probe.c'), str(path / 'hook.c'), '-o', str(exe), '-pthread'], check=True, timeout=60)
        subprocess.run([str(exe)], check=True, timeout=30,
                       env=dict(os.environ, ASAN_OPTIONS='detect_leaks=1', TSAN_OPTIONS='halt_on_error=1'))
