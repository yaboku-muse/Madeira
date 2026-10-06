// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Report file writer: "[ubi-host] <round> <field>=<number>" lines.
// The iOS app polls this file; probe-result=<code> is the terminal signal.
#include "dock_ubi.h"
#include <stdio.h>

static FILE *g_report = NULL;

void ubi_report_init(const char *path)
{
    if (!path || !*path)
        path = "C:\\madeira-dock-ubi.txt";
    g_report = fopen(path, "a");
}

void ubi_report(const char *round, const char *field, long long value)
{
    if (!g_report || !round || !field)
        return;
    // Numeric-only fields; the iOS side allowlists names.
    fprintf(g_report, "[ubi-host] %s %s=%lld\n", round, field, value);
    fflush(g_report);
}

void ubi_report_close(void)
{
    if (g_report) {
        fclose(g_report);
        g_report = NULL;
    }
}
