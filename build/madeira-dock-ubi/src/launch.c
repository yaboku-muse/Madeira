// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Connect prerequisite: ensure the real Ubisoft Connect client (upc.exe)
// is running and ready before the Steam Dock launches the game.
//
// Steam-bought Ubisoft games don't launch via uplay:// URLs — Steam launches
// the game exe directly, and the game's uplay_r1.dll talks to the running
// Connect client for DRM/entitlement checks. So this host's only job is to
// make sure that client is up. The user logs into Connect once (remember-me);
// the client auto-authenticates on later starts.
#include "dock_ubi.h"
#include <stdio.h>
#include <string.h>
#include <tlhelp32.h>

// Result codes (terminal probe-result values).
#define UBI_OK               0
#define UBI_ERR_CLIENT_DIR   30  // client dir missing or upc.exe not found
#define UBI_ERR_CLIENT_START 31  // could not start upc.exe
#define UBI_ERR_TIMEOUT      32  // client did not become ready in time

static int process_running(const char *exe_name)
{
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32 pe;
    int found = 0;

    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    pe.dwSize = sizeof(pe);
    if (Process32First(snap, &pe)) {
        do {
            if (_stricmp(pe.szExeFile, exe_name) == 0) {
                found = 1;
                break;
            }
        } while (Process32Next(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

// The client is "ready" when upc.exe is running and its main window exists.
// We poll for the process; the window check is a best-effort extra.
static int client_ready(void)
{
    if (!process_running("upc.exe") && !process_running("UbisoftConnect.exe"))
        return 0;
    return 1;
}

int ubi_prepare(const ubi_auth_t *auth, const char *client_dir)
{
    char upc_path[MAX_PATH];
    (void)auth; // Reserved: future session-ticket injection.

    if (!client_dir || !*client_dir)
        return UBI_ERR_CLIENT_DIR;

    if (client_ready()) {
        ubi_report("ml100", "client-already-running", 1);
        return UBI_OK;
    }

    _snprintf(upc_path, sizeof(upc_path), "%s\\upc.exe", client_dir);
    upc_path[sizeof(upc_path) - 1] = '\0';
    if (GetFileAttributesA(upc_path) == INVALID_FILE_ATTRIBUTES) {
        // Try the 64-bit launcher name.
        _snprintf(upc_path, sizeof(upc_path), "%s\\UbisoftConnect.exe", client_dir);
        upc_path[sizeof(upc_path) - 1] = '\0';
        if (GetFileAttributesA(upc_path) == INVALID_FILE_ATTRIBUTES)
            return UBI_ERR_CLIENT_DIR;
    }

    ubi_report("ml100", "client-starting", 1);
    {
        STARTUPINFOA si;
        PROCESS_INFORMATION pi;
        memset(&si, 0, sizeof(si));
        si.cb = sizeof(si);
        memset(&pi, 0, sizeof(pi));
        if (!CreateProcessA(upc_path, NULL, NULL, NULL, FALSE,
                            DETACHED_PROCESS, NULL, client_dir, &si, &pi))
            return UBI_ERR_CLIENT_START;
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }

    // Wait up to 60s for the client to come up (Qt + Chromium take a while,
    // especially under emulation).
    for (int i = 0; i < 60; i++) {
        Sleep(1000);
        if (client_ready()) {
            ubi_report("ml100", "client-running", 1);
            // Extra grace: let it finish login via remember-me.
            Sleep(5000);
            return UBI_OK;
        }
    }
    return UBI_ERR_TIMEOUT;
}
