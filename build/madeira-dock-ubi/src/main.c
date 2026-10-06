// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// dockhost-ubi.exe entry point.
//
// Env vars (MADEIRA_UBI_HOST_* namespace):
//   MADEIRA_UBI_HOST_LAUNCH      "1" = run the launch phase
//   MADEIRA_UBI_HOST_GAME_ID     Ubisoft numeric game ID (fallback if the
//                                handoff is absent; the handoff wins)
//   MADEIRA_UBI_HOST_LAUNCH_MODE "1" = multiplayer, else singleplayer
//   MADEIRA_UBI_HOST_CLIENT_DIR  Connect install dir
//                                (default "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher")
//   MADEIRA_UBI_HOST_LOG         report file path
//   MADEIRA_DOCK_AUTH_FILE       one-use MUBI0001 handoff path
//
// A named mutex (Local\MadeiraUbiHost) prevents concurrent runs.
// Terminal report: probe-result=<code> (0 = success).
#include "dock_ubi.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *getenv_d(const char *name, const char *dflt)
{
    const char *v = getenv(name);
    return (v && *v) ? v : dflt;
}

static int enabled(const char *name)
{
    const char *v = getenv(name);
    return v && v[0] == '1';
}

int main(void)
{
    HANDLE mutex;
    const char *log_path;
    const char *auth_path;
    const char *client_dir;
    ubi_auth_t auth;
    int auth_rc;
    int result = 0;

    mutex = CreateMutexA(NULL, FALSE, "Local\\MadeiraUbiHost");
    if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) {
        // Another instance is running; not fatal for a fire-and-forget URL.
        if (mutex)
            CloseHandle(mutex);
    }

    log_path = getenv_d("MADEIRA_UBI_HOST_LOG", "C:\\madeira-dock-ubi.txt");
    ubi_report_init(log_path);
    ubi_report("ml090", "host-start", 1);

    auth_path = getenv("MADEIRA_DOCK_AUTH_FILE");
    memset(&auth, 0, sizeof(auth));
    auth_rc = ubi_auth_consume(auth_path, &auth);
    ubi_report("ml090", "auth-consumed", auth_rc == 0 ? 1 : 0);
    if (auth_rc != 0) {
        // Fall back to the env game ID so a bare launch still works when
        // the client is already logged in interactively.
        const char *gid = getenv("MADEIRA_UBI_HOST_GAME_ID");
        if (gid && *gid) {
            size_t n = strlen(gid);
            auth.game_id = (char *)malloc(n + 1);
            if (auth.game_id) {
                memcpy(auth.game_id, gid, n + 1);
                auth.ticket = NULL;
            }
        }
    }

    if (enabled("MADEIRA_UBI_HOST_LAUNCH")) {
        unsigned mode = enabled("MADEIRA_UBI_HOST_LAUNCH_MODE") ? 1u : 0u;
        client_dir = getenv_d("MADEIRA_UBI_HOST_CLIENT_DIR",
                              "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher");
        result = ubi_launch(&auth, client_dir, mode);
        ubi_report("ml120", "launch-result", result);
    }

    ubi_report("ml999", "probe-result", result);
    ubi_report_close();
    ubi_auth_free(&auth);
    if (mutex)
        CloseHandle(mutex);
    return result;
}
