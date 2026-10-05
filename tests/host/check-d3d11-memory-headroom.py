#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile production mip-pressure configuration/decisions for both guest widths."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'dxmt/src/d3d11/d3d11_texture_device.cpp').read_text()
production = source[source.index('struct MipClampAutoConfig {'):source.index('template <typename tag>\nHRESULT CreateDeviceTextureInternal')]
code = r'''
#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <type_traits>
#include "d3d11_mip_clamp_policy.hpp"
using namespace dxmt;
#define ERR(...) do {} while (0)
constexpr bool kMadeira32BitModule = ARCH32;
static std::string option, environment;
static int threshold = 1536;
struct Config {
    static Config &getInstance() { static Config c; return c; }
    template<typename T> T getOption(const std::string &key, T fallback) {
        if constexpr (std::is_same_v<T, std::string>) return option;
        else return threshold;
    }
};
namespace env { std::string getEnvVar(const std::string &) { return environment; } }
struct madeira_ctl_args { int op; uint64_t ptr, len; int ret; };
static int queries;
static bool available = true;
static int64_t headroom = 4096, footprint = 2048;
static void MadeiraCtl(madeira_ctl_args *a) {
    assert(a->op == 7); queries++;
    if (available) { a->ret = 1; a->len = uint64_t(headroom) << 20; a->ptr = uint64_t(footprint) << 20; }
}
'''
code += production
code += r'''
int main(int argc, char **argv) {
    assert(argc == 2);
    std::string scenario = argv[1];
    if (scenario == "off-config") { option = " Off "; environment = "on"; }
    if (scenario == "off-environment") { option = "on"; environment = "FALSE"; }
    if (scenario == "zero-threshold") threshold = 0;
    if (scenario == "negative-threshold") threshold = -1;
    if (scenario == "unavailable") available = false;
    if (scenario == "off-config" || scenario == "off-environment" ||
        scenario == "zero-threshold" || scenario == "negative-threshold") {
        assert(MipClampAutoBias(4096, 4096, 13) == 0 && queries == 0);
    } else if (scenario == "unavailable") {
        for (int i = 0; i < 32; i++) assert(MipClampAutoBias(4096, 4096, 13) == 0);
        assert(queries == 1);
    } else {
        assert(scenario == "default");
        assert(GetMipClampAutoConfig().enabled);
        assert(MipClampAutoBias(512, 512, 10) == 0 && queries == 0);
        assert(MipClampAutoBias(4096, 4096, 1) == 0 && queries == 0);
        assert(MipClampAutoBias(2050, 2050, 12) == 0 && queries == 0);
        assert(MipClampAutoBias(4096, 4096, 13) == 0 && queries == 1);
        // Approaching pressure refreshes every eligible allocation, then
        // crossing it drops one physical level. Recovery leaves new ones intact.
        headroom = 2000;
        for (int i = 0; i < 15; i++) assert(MipClampAutoBias(4096, 4096, 13) == 0);
        assert(g_auto_headroom_mb == 2000);
        headroom = 1000; footprint = 5000;
        assert(MipClampAutoBias(4096, 4096, 13) == 1);
        assert(g_auto_footprint_mb == 5000);
        headroom = 4000;
        assert(MipClampAutoBias(4096, 4096, 13) == 0);
        assert(!g_auto_pressure_logged);
    }
    printf("guest-%s %s passed\n", ARCH32 ? "32" : "64", scenario.c_str());
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    path.joinpath('probe.cpp').write_text(code)
    compiler = shutil.which('clang++') or shutil.which('c++')
    if not compiler:
        raise SystemExit('Host C++ compiler required; run the host regression workflow.')
    for width in (0, 1):
        executable = path / f'probe-{width}'
        subprocess.run([compiler, '-std=c++17', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
                        f'-DARCH32={width}', '-I', str(root / 'dxmt/src/d3d11'),
                        str(path / 'probe.cpp'), '-o', str(executable)], check=True, timeout=60)
        for scenario in ('default', 'off-config', 'off-environment', 'zero-threshold', 'negative-threshold', 'unavailable'):
            subprocess.run([str(executable), scenario], check=True, timeout=30)
print('check-d3d11-memory-headroom: production decisions/configuration passed for both guest widths')
