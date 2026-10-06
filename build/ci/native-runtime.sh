#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$R"
bash build/ci/fetch-mingw.sh
export PATH="$(brew --prefix bison)/bin:$(brew --prefix llvm@20)/bin:$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:$PATH"
mkdir -p research wine/build-macos wine/build-arm64ec
if [ ! -d research/freetype/.git ]; then
    git init research/freetype
    git -C research/freetype remote add origin https://github.com/freetype/freetype.git
    git -C research/freetype fetch --depth 1 origin 42608f77f20749dd6ddc9e0536788eaad70ea4b5
    git -C research/freetype checkout --detach FETCH_HEAD
fi
[ "$(git -C research/freetype rev-parse HEAD)" = 42608f77f20749dd6ddc9e0536788eaad70ea4b5 ]
# Native configure supplies generated Unix feature headers and WIDL headers.
(cd wine/build-macos && ../configure --enable-archs=aarch64 --without-x --disable-tests --enable-winegstreamer)
make -C wine/build-macos -j3 include/all dlls/ntdll/unix/version.c
(cd wine/build-arm64ec && ../configure --enable-archs=arm64ec --without-x --disable-tests --enable-winegstreamer)
make -C wine/build-arm64ec -j3 include/all
bash build/wine-pe/build-ntdll.sh
# The LLVM bin directory above is for Mach-O objcopy. Select Xcode's native
# compiler explicitly for host sanitizer tests instead of inheriting its clang.
HOST_CC="$(xcrun --find clang)" bash build/madeira-dock/build.sh --check
bash build/madeira-dock-ubi/build.sh
(cd build/gnutls-ios/src && shasum -a 256 -c SHA256SUMS)
bash build/gnutls-ios/build.sh
bash build/ffmpeg/build.sh
bash build/freetype-ios/build.sh
bash build/ntdll-unix/build.sh
bash build/wineserver/build.sh
bash build/win32u-unix/build.sh
rustup target add aarch64-apple-ios
bash build/rppairing-ios/build.sh
