// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// dockhost-ubi: headless Ubisoft Connect driver for Madeira.
//
// Unlike the Steam dockhost (which drives Steam's private client APIs
// directly), Ubisoft exposes no programmatic launch interface. Everything
// goes through the uplay:// URL protocol handled by the real Connect
// client. This host therefore:
//   1. Reads a one-use auth handoff (Ubisoft session ticket + remember-me
//      token, written by the iOS app after the user logs in via the
//      documented web API).
//   2. Ensures the real Ubisoft Connect client (upc.exe) is running.
//   3. Fires uplay://launch/{game_id}/{mode} via ShellExecute.
//   4. Reports progress to the report file the iOS app polls.
//
// It does not reimplement the client, DRM, or downloads.
#ifndef DOCK_UBI_H
#define DOCK_UBI_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Report file: lines of "[ubi-host] <round> <field>=<number>".
// The iOS app polls this; probe-result=<code> is terminal (0 = success).
// ---------------------------------------------------------------------------
void ubi_report_init(const char *path);
void ubi_report(const char *round, const char *field, long long value);
void ubi_report_close(void);

// ---------------------------------------------------------------------------
// Auth handoff: binary envelope written by the iOS app, consumed once.
//
// Layout (all integers little-endian):
//   0x00  char[8]   magic "MUBI0001"
//   0x08  u16       ticket_len  (Ubisoft session ticket, UTF-8)
//   0x0A  u16       remember_len (remember-me token, UTF-8, may be 0)
//   0x0C  u16       user_id_len  (Ubisoft user ID, UTF-8)
//   0x0E  u16       game_id_len  (Ubisoft numeric game ID as text, UTF-8)
//   0x10  bytes     ticket, remember-me token, user ID, game ID
// Total capped at 16KB. The file is opened exclusively and deleted on
// consume; memory is zeroed after use.
// ---------------------------------------------------------------------------
#define UBI_AUTH_MAGIC "MUBI0001"
#define UBI_AUTH_MAX (16u * 1024u)

typedef struct {
    char *ticket;       // heap, zeroed on free
    char *remember_me;  // heap, may be NULL
    char *user_id;      // heap
    char *game_id;      // heap, numeric text
} ubi_auth_t;

// Returns 0 on success, nonzero on failure (file missing, bad magic,
// truncated, oversize). On success the file is deleted.
int ubi_auth_consume(const char *path, ubi_auth_t *out);
void ubi_auth_free(ubi_auth_t *a);

// ---------------------------------------------------------------------------
// Prepare: ensure upc.exe is running and ready. The Steam Dock launches the
// game afterwards; the game's uplay_r1.dll talks to this client for DRM.
// Returns a numeric result code (0 = ready; see launch.c for codes).
// ---------------------------------------------------------------------------
int ubi_prepare(const ubi_auth_t *auth, const char *client_dir);

#endif // DOCK_UBI_H
