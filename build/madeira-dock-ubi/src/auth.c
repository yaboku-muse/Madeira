// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// One-use Ubisoft auth handoff. The iOS app writes the MUBI0001 envelope
// after the user completes the Ubisoft web login; this host consumes
// (reads + deletes) it before doing anything with the tokens.
#include "dock_ubi.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void zero_free(char *p)
{
    if (p) {
        memset(p, 0, strlen(p));
        free(p);
    }
}

void ubi_auth_free(ubi_auth_t *a)
{
    if (!a)
        return;
    zero_free(a->ticket);
    zero_free(a->remember_me);
    zero_free(a->user_id);
    zero_free(a->game_id);
    memset(a, 0, sizeof(*a));
}

int ubi_auth_consume(const char *path, ubi_auth_t *out)
{
    FILE *f;
    long size;
    unsigned char *buf = NULL;
    unsigned char *p;
    uint16_t ticket_len, remember_len, user_id_len, game_id_len;
    size_t need;

    if (!path || !*path || !out)
        return 1;
    memset(out, 0, sizeof(*out));

    f = fopen(path, "rb");
    if (!f)
        return 2;

    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 16 || (unsigned long)size > UBI_AUTH_MAX) {
        fclose(f);
        return 3;
    }
    buf = (unsigned char *)malloc((size_t)size);
    if (!buf) {
        fclose(f);
        return 4;
    }
    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        free(buf);
        fclose(f);
        return 5;
    }
    fclose(f);
    // Delete on consume: single use.
    remove(path);

    if (memcmp(buf, UBI_AUTH_MAGIC, 8) != 0) {
        memset(buf, 0, (size_t)size);
        free(buf);
        return 6;
    }
    p = buf + 8;
    ticket_len = (uint16_t)(p[0] | (p[1] << 8)); p += 2;
    remember_len = (uint16_t)(p[0] | (p[1] << 8)); p += 2;
    user_id_len = (uint16_t)(p[0] | (p[1] << 8)); p += 2;
    game_id_len = (uint16_t)(p[0] | (p[1] << 8)); p += 2;

    need = 16u + ticket_len + remember_len + user_id_len + game_id_len;
    if (need != (size_t)size || ticket_len == 0 || game_id_len == 0) {
        memset(buf, 0, (size_t)size);
        free(buf);
        return 7;
    }
    // Sanity: game ID must be numeric text.
    for (uint16_t i = 0; i < game_id_len; i++) {
        if (p[ticket_len + remember_len + user_id_len + i] < '0' ||
            p[ticket_len + remember_len + user_id_len + i] > '9') {
            memset(buf, 0, (size_t)size);
            free(buf);
            return 8;
        }
    }

#define TAKE(dst, len) do { \
        (dst) = (char *)malloc((len) + 1); \
        if (!(dst)) { ubi_auth_free(out); memset(buf, 0, (size_t)size); free(buf); return 4; } \
        memcpy((dst), p, (len)); (dst)[(len)] = '\0'; p += (len); \
    } while (0)

    TAKE(out->ticket, ticket_len);
    if (remember_len)
        TAKE(out->remember_me, remember_len);
    TAKE(out->user_id, user_id_len);
    TAKE(out->game_id, game_id_len);
#undef TAKE

    memset(buf, 0, (size_t)size);
    free(buf);
    return 0;
}
