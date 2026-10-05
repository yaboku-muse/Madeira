#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise production startup-window repair with synthetic Wine windows."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'build/win32u-unix/driver_ios.c').read_text()
block = source.split('#define WINIOS_RENDER_START_MAX', 1)[1].split('/* ============================================================ *', 1)[0]
block = '#define WINIOS_RENDER_START_MAX' + block
winios = (root / 'app/Madeira/Winios/Winios.m').read_text()
assert 'winios_drv_repair_render_windows();' in winios.split('BOOL winios_pProcessEvents(DWORD mask) {', 1)[1].split('static unsigned int cnt;', 1)[0]
assert 'winios_drv_render_window_created((HWND)hwnd);' in winios
assert 'winios_drv_render_window_forget(hwnd);' in winios
assert 'winios_drv_render_window_forget(NULL);' in winios
prelude = r'''
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
typedef void *HWND;
typedef uint32_t DWORD;
typedef int INT;
typedef struct { int left, top, right, bottom; } RECT;
struct window_rects { RECT window, client; };
#define WS_CHILD 0x40000000
#define WS_DISABLED 0x08000000
#define WS_VISIBLE 0x10000000
#define WS_MINIMIZE 0x20000000
#define WS_EX_TOOLWINDOW 0x80
#define WS_EX_DLGMODALFRAME 1
#define GWL_STYLE 0
#define GWL_EXSTYLE 1
#define GA_PARENT 1
#define GW_OWNER 1
#define COORDS_SCREEN 1
#define MDT_DEFAULT 1
#define SW_RESTORE 9
#define SWP_NOACTIVATE 0x10
#define SWP_NOZORDER 0x4
static DWORD thread_id = 1, clock_ms;
static RECT screen = {0, 0, 1408, 648};
static int restores, positions, destroy_on_restore, valid_on_restore;
struct fake { HWND hwnd; DWORD pid, tid, style, exstyle; int owned, desktop; struct window_rects rects; };
static struct fake fakes[64];
static int nfakes;
static pthread_mutex_t *registry_lock;
static void unlocked(void) {
    if (!registry_lock) return;
    assert(pthread_mutex_trylock(registry_lock) == 0);
    pthread_mutex_unlock(registry_lock);
}
static struct fake *lookup(HWND hwnd) {
    for (int i = 0; i < nfakes; i++) if (fakes[i].hwnd == hwnd) return &fakes[i];
    return NULL;
}
static DWORD get_window_long(HWND hwnd, int which) { unlocked(); struct fake *f = lookup(hwnd); return f ? (which == GWL_STYLE ? f->style : f->exstyle) : 0; }
static DWORD get_window_thread(HWND hwnd, DWORD *pid) { unlocked(); struct fake *f = lookup(hwnd); if (pid) *pid = f ? f->pid : 0; return f ? f->tid : 0; }
static HWND NtUserGetAncestor(HWND hwnd, int kind) { unlocked(); assert(kind == GA_PARENT); struct fake *f = lookup(hwnd); return f && !f->desktop ? (HWND)(uintptr_t)99 : NULL; }
static HWND get_window_relative(HWND hwnd, int kind) { unlocked(); assert(kind == GW_OWNER); struct fake *f = lookup(hwnd); return f && f->owned ? (HWND)(uintptr_t)99 : NULL; }
static RECT get_virtual_screen_rect(int dpi, int kind) { unlocked(); (void)dpi; (void)kind; return screen; }
static int get_thread_dpi(void) { unlocked(); return 96; }
static int get_window_rects(HWND hwnd, int coords, struct window_rects *rects, int dpi) { unlocked(); (void)coords; (void)dpi; struct fake *f = lookup(hwnd); if (!f) return 0; *rects = f->rects; return 1; }
static DWORD NtGetTickCount(void) { return clock_ms; }
static DWORD GetCurrentThreadId(void) { return thread_id; }
void winios_drv_render_window_forget(HWND hwnd);
static int NtUserShowWindow(HWND hwnd, int how) {
    unlocked(); assert(how == SW_RESTORE); restores++;
    struct fake *f = lookup(hwnd); assert(f);
    if (destroy_on_restore) { winios_drv_render_window_forget(hwnd); f->hwnd = NULL; return 0; }
    f->style &= ~WS_MINIMIZE;
    if (valid_on_restore) f->rects.window = f->rects.client = screen;
    return 1;
}
static int NtUserSetWindowPos(HWND hwnd, HWND after, int x, int y, int w, int h, unsigned flags) {
    unlocked(); assert(!after && flags == (SWP_NOACTIVATE | SWP_NOZORDER));
    assert(x == screen.left && y == screen.top && w == screen.right - screen.left && h == screen.bottom - screen.top);
    positions++; struct fake *f = lookup(hwnd); assert(f); f->rects.window = f->rects.client = screen;
    return 1;
}
'''
checks = r'''
static HWND add(int id, int valid) {
    assert(nfakes < 64);
    struct fake *f = &fakes[nfakes++];
    *f = (struct fake){.hwnd = (HWND)(uintptr_t)id, .pid = (DWORD)id, .tid = 1, .style = WS_VISIBLE};
    f->rects.window = f->rects.client = valid ? screen : (RECT){0, 0, 0, 0};
    return f->hwnd;
}
static void reset(void) {
    winios_drv_render_window_forget(NULL); nfakes = 0; memset(fakes, 0, sizeof(fakes));
    restores = positions = destroy_on_restore = valid_on_restore = 0; clock_ms = 0; thread_id = 1;
}
int main(void) {
    registry_lock = &winios_render_start_lock;
    HWND hwnd = add(1, 0);
    winios_drv_render_window_created(hwnd);
    clock_ms = 499; winios_drv_repair_render_windows(); assert(!positions);
    clock_ms = 500; thread_id = 2; winios_drv_repair_render_windows(); assert(!positions);
    thread_id = 1; winios_drv_repair_render_windows(); assert(positions == 1);
    winios_drv_repair_render_windows(); assert(positions == 1);
    lookup(hwnd)->style |= WS_MINIMIZE;
    winios_drv_render_window_created(hwnd); clock_ms += 1000; winios_drv_repair_render_windows();
    assert(positions == 1 && !restores); /* intentional later minimize */
    reset(); hwnd = add(1, 1); lookup(hwnd)->rects.window = lookup(hwnd)->rects.client = (RECT){-32000,-32000,-31000,-31000};
    winios_drv_render_window_created(hwnd); clock_ms = 500; winios_drv_repair_render_windows(); assert(positions == 1);
    reset(); hwnd = add(1, 0); lookup(hwnd)->style |= WS_MINIMIZE; valid_on_restore = 1;
    winios_drv_render_window_created(hwnd); clock_ms = 500; winios_drv_repair_render_windows(); assert(restores == 1 && !positions);
    reset(); hwnd = add(1, 0); lookup(hwnd)->style |= WS_MINIMIZE; destroy_on_restore = 1;
    winios_drv_render_window_created(hwnd); clock_ms = 500; winios_drv_repair_render_windows(); assert(restores == 1 && !positions);
    reset(); hwnd = add(1, 0); winios_drv_render_window_created(hwnd);
    lookup(hwnd)->rects.window = lookup(hwnd)->rects.client = screen;
    clock_ms = 500; winios_drv_repair_render_windows(); assert(!positions);
    reset(); hwnd = add(1, 1); winios_drv_render_window_created(hwnd);
    lookup(hwnd)->rects.client = (RECT){0,0,0,0}; clock_ms = 500; winios_drv_repair_render_windows(); assert(!positions);
    for (int kind = 0; kind < 6; kind++) {
        reset(); hwnd = add(1, 0); struct fake *f = lookup(hwnd);
        if (kind == 0) f->style |= WS_CHILD;
        if (kind == 1) f->style |= WS_DISABLED;
        if (kind == 2) f->exstyle = WS_EX_TOOLWINDOW;
        if (kind == 3) f->exstyle = WS_EX_DLGMODALFRAME;
        if (kind == 4) f->owned = 1;
        if (kind == 5) f->style = 0;
        winios_drv_render_window_created(hwnd); clock_ms = 500; winios_drv_repair_render_windows(); assert(!positions && !restores);
    }
    reset(); hwnd = add(1, 0); winios_drv_render_window_created(hwnd); winios_drv_render_window_forget(hwnd);
    clock_ms = 500; winios_drv_repair_render_windows(); assert(!positions);
    reset(); hwnd = add(1, 0); winios_drv_render_window_created(hwnd); lookup(hwnd)->pid = 2;
    clock_ms = 500; winios_drv_repair_render_windows(); assert(!positions);
    reset(); hwnd = add(1, 0); winios_drv_render_window_created(hwnd);
    HWND secondary = add(2, 0); lookup(secondary)->pid = 1; winios_drv_render_window_created(secondary);
    clock_ms = 500; winios_drv_repair_render_windows(); assert(positions == 1 && lookup(secondary)->rects.client.right == 0);
    reset(); clock_ms = UINT32_MAX - 100; hwnd = add(1, 0); winios_drv_render_window_created(hwnd);
    clock_ms = 398; winios_drv_repair_render_windows(); assert(!positions);
    clock_ms = 399; winios_drv_repair_render_windows(); assert(positions == 1);
    reset();
    for (int i = 1; i <= 40; i++) winios_drv_render_window_created(add(i, 0));
    clock_ms = 500; winios_drv_repair_render_windows(); assert(positions == 32);
    struct window_rects edge = { .window = {INT32_MIN,INT32_MIN,INT32_MIN+1,INT32_MIN+1}, .client = {0,0,1,1} };
    assert(winios_render_geometry_invalid(&edge, screen, 0));
    assert(!winios_render_geometry_invalid(&edge, (RECT){0,0,0,0}, 0));
    puts("PASS: production render-window grace/ownership/geometry/lifecycle checks");
    return 0;
}
'''
compiler = shutil.which('clang') or shutil.which('cc')
assert compiler, 'a C compiler is required'
with tempfile.TemporaryDirectory(prefix='madeira-window-repair-') as temporary:
    path = Path(temporary)
    (path / 'check.c').write_text(prelude + block + checks)
    subprocess.run([compiler, '-std=gnu11', '-O1', '-g', '-fsanitize=address,undefined',
                    '-fno-sanitize-recover=undefined', '-pthread', str(path / 'check.c'),
                    '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
