#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""A child's correct callback dispatcher is not a session-owner mismatch."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
signal = (root / 'build/ntdll-unix/signal_arm64_ios.c').read_text(encoding='utf-8')
loader = (root / 'build/ntdll-unix/loader_ios.c').read_text(encoding='utf-8')


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]


lookup = function(loader, 'const struct ios_ntdll_funcs *ios_ntdll_funcs_for_peb(')
expected = function(signal, 'static void *ios_callback_dispatcher_for_peb(')
callback = function(signal, 'NTSTATUS KeUserModeCallback(')
assert 'void *disp = IOS_PFUNC(KiUserCallbackDispatcher);' in callback
assert 'int cross = disp != expected;' in callback
assert 'ios_callback_dispatcher_for_peb( NtCurrentTeb()->Peb )' in callback
assert 'extern PEB *peb;' not in callback
assert 'NtCurrentTeb()->Peb == peb' not in callback
assert 'call_user_mode_callback( sp, ret_ptr, ret_len, disp, NtCurrentTeb() )' in callback
assert 'CALLBACK DISPATCHER OWNER MISMATCH' in callback
code = r'''
#include <assert.h>
#include <stdio.h>
#include <stddef.h>
struct ios_ntdll_funcs { void *KiUserCallbackDispatcher; };
struct ident { void *peb, *ntdll_module; struct ios_ntdll_funcs funcs; };
static struct ident ios_proc_idents[4];
static int ios_proc_ident_count;
static int session_peb, child_peb, sibling_peb, unregistered_peb;
static int session_dispatcher, child_dispatcher, sibling_dispatcher;
static void *pKiUserCallbackDispatcher = &session_dispatcher;
'''
code += lookup + '\n' + expected
code += r'''
int main(void) {
  ios_proc_idents[0] = (struct ident){&child_peb, &child_dispatcher, {&child_dispatcher}};
  ios_proc_idents[1] = (struct ident){&sibling_peb, &sibling_dispatcher, {&sibling_dispatcher}};
  ios_proc_ident_count = 2;
  // The supplied Teardown warning: mutable global peb points to this child,
  // whose TEB and private ntdll also correctly belong to this child.
  void *mutable_global_peb = &child_peb;
  void *thread_peb = &child_peb, *disp = &child_dispatcher;
  assert(disp != pKiUserCallbackDispatcher && thread_peb == mutable_global_peb);
  assert(disp == ios_callback_dispatcher_for_peb(thread_peb));
  // Actual crossed ownership remains detectable, for either parent or sibling.
  assert(disp != ios_callback_dispatcher_for_peb(&session_peb));
  assert(disp != ios_callback_dispatcher_for_peb(&sibling_peb));
  assert(ios_callback_dispatcher_for_peb(&sibling_peb) == &sibling_dispatcher);
  assert(ios_callback_dispatcher_for_peb(&session_peb) == &session_dispatcher);
  assert(ios_callback_dispatcher_for_peb(NULL) == &session_dispatcher);
  assert(ios_callback_dispatcher_for_peb(&unregistered_peb) == &session_dispatcher);
  // Same-architecture children without a private ntdll use the session image.
  ios_proc_idents[2] = (struct ident){&unregistered_peb, NULL, {&sibling_dispatcher}};
  ios_proc_ident_count = 3;
  assert(ios_callback_dispatcher_for_peb(&unregistered_peb) == &session_dispatcher);
  puts("PASS: mutable-global false positive, parent/child/sibling ownership and session fallback");
}
'''
compiler = shutil.which('clang') or shutil.which('cc')
if not compiler:
    raise SystemExit('Host C compiler required; run the host regression workflow.')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('probe.c').write_text(code)
    executable = path / 'probe'
    subprocess.run([compiler, '-std=c11', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                    str(path / 'probe.c'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
