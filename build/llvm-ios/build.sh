#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
# Reconstruct the pinned LLVM 15.0.7 host tablegen and iOS libraries used by DXMT.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
REV=8dfdcc7b7bf66834a761bd8de445840ef68e4d1a
SRC="$R/toolchains/llvm-project"
HOST="$R/toolchains/llvm-host-build"
IOS="$R/toolchains/llvm-ios-build"
mkdir -p "$R/toolchains"
if [ ! -d "$SRC/.git" ]; then
    git init "$SRC"
    git -C "$SRC" remote add origin https://github.com/llvm/llvm-project.git
    git -C "$SRC" fetch --depth 1 origin "$REV"
    git -C "$SRC" checkout --detach FETCH_HEAD
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$REV" ] || { echo "LLVM source revision mismatch" >&2; exit 1; }
# LLVM 15's AddLLVM assumes every non-Darwin target uses GNU ld. iOS uses
# Apple ld too; apply the documented single-line Darwin|iOS port adjustment.
python3 - "$SRC/llvm/cmake/modules/AddLLVM.cmake" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('${CMAKE_SYSTEM_NAME} MATCHES "Darwin"', '${CMAKE_SYSTEM_NAME} MATCHES "Darwin|iOS"')
assert '${CMAKE_SYSTEM_NAME} MATCHES "Darwin|iOS"' in s
p.write_text(s)
PY
# HandleLLVMOptions has a separate ELF-only -z,defs guard. iOS must be
# excluded alongside Darwin before CMake configures the shared LTO target.
python3 - "$SRC/llvm/cmake/modules/HandleLLVMOptions.cmake" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('MATCHES "Darwin|FreeBSD|OpenBSD|DragonFly|AIX|SunOS|OS390"',
              'MATCHES "Darwin|iOS|FreeBSD|OpenBSD|DragonFly|AIX|SunOS|OS390"')
assert 'MATCHES "Darwin|iOS|FreeBSD|OpenBSD|DragonFly|AIX|SunOS|OS390"' in s
p.write_text(s)
PY
cmake -S "$SRC/llvm" -B "$HOST" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_TERMINFO=OFF
cmake --build "$HOST" --target llvm-tblgen -j2
cmake -S "$SRC/llvm" -B "$IOS" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 \
    -DLLVM_TARGET_ARCH=host -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= \
    -DLLVM_TABLEGEN="$HOST/bin/llvm-tblgen" -DLLVM_BUILD_TOOLS=OFF -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF
cmake --build "$IOS" --target llvm-libraries -j2
test -f "$IOS/lib/libLLVMCore.a"
