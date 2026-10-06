// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Game launch: ensure the real Ubisoft Connect client (upc.exe) is running,
// then fire uplay://launch/{game_id}/{mode} via ShellExecute. The client
// handles DRM, entitlement checks, downloads, and the actual game process —
// this host only triggers it, mirroring how Steam/GOG/Playnite launch
// Ubisoft games on desktop.
#include "dock_ubi.h"
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <tlhelp32.h>

// Result codes (terminal probe-result values).
#define UBI_OK                  0
#define UBI_ERR_CLIENT_DIR      30  // client dir missing or upc.exe not found
#define UBI_ERR_CLIENT_START    31  // could not start upc.exe
#define UBI_ERR_URL             32  // ShellExecute on the uplay:// URL failed
#define UBI_ERR_NO_GAME_ID      33  // game ID missing from handoff

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

// Start upc.exe if it isn't running. Returns 0 on success.
static int ensure_client(const char *client_dir)
{
    char upc_path[MAX_PATH];

    if (process_running("upc.exe") || process_running("UbisoftConnect.exe"))
        return 0;
    if (!client_dir || !*client_dir)
        return UBI_ERR_CLIENT_DIR;

    _snprintf(upc_path, sizeof(upc_path), "%s\\upc.exe", client_dir);
    upc_path[sizeof(upc_path) - 1] = '\0';

    {
        DWORD attrs = GetFileAttributesA(upc_path);
        if (attrs == INVALID_FILE_ATTRIBUTES)
            return UBI_ERR_CLIENT_DIR;
    }
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
    // Give the client a moment to register its protocol handler.
    Sleep(5000);
    return 0;
}

int ubi_launch(const ubi_auth_t *auth, const char *client_dir, unsigned mode)
{
    char url[128];
    HINSTANCE rc;

    if (!auth || !auth->game_id || !*auth->game_id)
        return UBI_ERR_NO_GAME_ID;

    ubi_report("ml100", "client-ensure", 1);
    {
        int r = ensure_client(client_dir);
        if (r != 0) {
            ubi_report("ml100", "client-ensure", 0);
            return r;
        }
    }
    ubi_report("ml100", "client-running", 1);

    // uplay://launch/{game_id}/{mode} — mode 0 = singleplayer, 1 = multiplayer.
    _snprintf(url, sizeof(url), "uplay://launch/%s/%u", auth->game_id, mode ? 1u : 0u);
    url[sizeof(url) - 1] = '\0';
    ubi_report("ml110", "url-fire", 1);

    rc = ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)rc <= 32) {
        ubi_report("ml110", "url-fire", 0);
        return UBI_ERR_URL;
    }
    ubi_report("ml110", "url-fired", 1);
    return UBI_OK;
}
