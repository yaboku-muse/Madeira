# Building Madeira from a clean checkout (reproducibility record, 2026-09-16)

## Fork source retrieval update (2026-10-04)

A Windows `git clone --recurse-submodules` of upstream `willfaust/Madeira` at
`bbbf8d0` completed, including FEX's nested dependencies and the Madeira Wine,
DXMT and Dock forks. This supersedes the historical statement below that those
upstream submodule commits were only local. This compatibility fork pins its
changed FEX, Wine and Dock commits to `llucasandersen/FEX`,
`llucasandersen/wine` and `llucasandersen/madeira-dock` in `.gitmodules`.
These retain the Madeira fork histories; DXMT is now pinned to the preserved
history `llucasandersen/dxmt` fork as well. FEX's nested rpmalloc fork remains
the original Madeira fork. After checkout, run
`git submodule update --init --recursive` and verify `git submodule status` has
no leading `-` or `+` entries before building.

This is source-retrieval verification on Windows, not a clean macOS build or
device test. The inputs and native build steps below remain required. The
`steam-launch-host.yml` and Dock `host-checks.yml` workflows exercise portable
source tests only; they do not build or validate an IPA.

## Diagnostic iOS build workflow

`ios-test-ipa.yml` is a manually triggered macOS 26 / Xcode 26.6 workflow.
It builds the pinned LLVM 15 iOS libraries, native FEX, Wine Unix libraries,
the changed ARM64EC ntdll, Dock, the GnuTLS stack, FFmpeg, FreeType, pairing,
DXMT's Metal side and the Debug app. This workflow is being verified from a
clean GitHub runner; a workflow file by itself is not evidence of a successful
build. Logs and failed compiler outputs are retained for diagnosis.

The native runtime job in run 37233256882 reached the rebuilt ARM64EC ntdll
at 20:48 UTC, then produced no further output before its two-hour timeout.
Runner cleanup terminated a `test-probe` process from Dock's host checks.
The runtime PATH placed Homebrew LLVM 20 before the Windows cross compiler,
and Dock's default host compiler lookup inherited that `clang`. The next build
selects Xcode's native compiler through the existing `HOST_CC` option and
bounds the complete Dock host-check process group to 300 seconds. A timeout
fails the build; no test is skipped. The exact cause inside the hung process
is not established by this log. The compiler selection change and remaining
runtime components require a new clean build before claiming resolution.
The retry in run 37241379231 selected Apple clang 21 but failed immediately
on missing `assert.h`. The wrapper now resolves and exports the macOS SDK
only within the host-check subprocess scope. This leaves the subsequent PE
cross compilation's SDK setup unchanged. The next retry must verify the host
checks and remaining runtime stages.
Run 37241729037 passed Dock's host sanitizer suite with the explicit Xcode
compiler and macOS SDK, then built the GnuTLS stack, FFmpeg and FreeType and
compiled 36 of 37 native ntdll units. `server_ios.c` failed because the public
iPhoneOS SDK's `rusage_info_v6` has no `ri_page_wait_time_mach` member. The
optional `[xp]` diagnostic now labels page-wait time `pgw=unavailable` and keeps
the other counters; it does not read a guessed reserved field or claim zero
wait time. [Apple's public structure](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)
also has no such member. The native ntdll script now rejects any compile
failure before archive assembly, so stale objects cannot hide that failure in
an incremental build. A new native compile and the remaining runtime stages
are required before the runtime artifact is considered verified.

The clean runtime build passed in
[run 37242307604](https://github.com/llucasandersen/Madeira/actions/runs/37242307604)
at Madeira `a793ece`: native ntdll compiled 37 units with no failures, native
win32u compiled 46 with no failures, and Wine server and the Rust pairing
archive completed. Dock's sanitizer suite passed, including its 11 bootstrap
scenarios and 101 validation cases. The downloaded runtime archive has SHA-256
`06af35cd8180e6787463f64e047d1b4f86ad2cb9d761bff6726d68440180fa73`.
Its ntdll contains the PE diagnostic marker, and Dock contains the new launch
option environment name as UTF-16LE, matching `GetEnvironmentVariableW` in
the source. Packaging and verification checks now use that encoding; the
earlier ASCII check would reject the correctly compiled Dock. This is runtime
component evidence, with the DXMT/app build and phone tests still pending.

The app job in that run compiled 86 DXMT units but failed
`airconv_context.cpp`: the standalone iOS script had omitted the generated
`air_msad.h`, `air_samplepos.h` and `air_tessellation.h` dependencies present
in the pinned DXMT Meson build. It now compiles those three pinned Metal
sources into AIR bitcode and embeds each with `xxd`, before compiling the
consumer, using Meson's Metal 3.1 / AIR macOS 14 target and symbol names.
These are bitcode inputs to LLVM linking, not metallib containers. The next
clean DXMT build must verify generation and archive assembly; no app build
or phone rendering pass is claimed for the failed run.

Run 37243316500 at Madeira `7352baf` generated all three AIR headers,
compiled all 87 DXMT units with no failures and assembled the combined
DXMT/LLVM archive (88,486,704 bytes). The following Xcode app build failed on
`FEXCore/Config/ConfigValues.inl`: the earlier native FEX artifact file list
included `.h`, `.hpp` and `.inc`, but omitted generated `.inl` headers.
Both `ConfigValues.inl` and `ConfigOptions.inl` are CMake outputs consumed by
`Config.h`. The workflow now retains `.inl` files and requires both headers
before upload and after restore. The older FEX artifact is insufficient for
app compilation; rebuild it with this workflow instead of reusing run
37234579200. Native FEX compilation previously passed, but the corrected
artifact transfer and complete Xcode app build still require verification.

The clean FEX rebuild and corrected artifact upload passed in
[run 37243852619](https://github.com/llucasandersen/Madeira/actions/runs/37243852619)
at Madeira `3fc0f54` / FEX `259f3ba7f`. The downloaded archive has SHA-256
`75f628cf42b5d12a42e2084b595cc6670e1f89995a92b5d333f99131ce8788d9`
and includes both nonempty configuration `.inl` headers and seven native
static libraries. That run's app job must still verify compilation with the
restored headers, linking and IPA packaging.

That app job restored the headers and compiled the app, but failed linking
`_rpm_cas_snapshot_take` from FEX `ContextImpl::CompileBlock`. FEX's CMake
configuration explicitly disables rpmalloc on Apple; the optional remote-free
diagnostic call nevertheless remained unconditional in `Core.cpp`. The fork
now defines `ENABLE_FEX_ALLOCATOR` for the core object target when the
allocator is enabled, and guards the rpmalloc-only declaration and sampler
with it. Native Apple builds keep their existing allocator policy; Windows
guest builds retain the snapshot diagnostic with rpmalloc enabled. A new
native link, both guest source builds and the full host suite must verify
this change. No fake snapshot implementation or undefined-symbol linker
suppression is used.

At Madeira `e6f6a2c` / FEX `b28076559`, the changed source compiled for
native iOS in run 37244570613 and for
[ARM64EC guests in run 37244572266](https://github.com/llucasandersen/Madeira/actions/runs/37244572266)
and [WOW64 guests in run 37244573651](https://github.com/llucasandersen/Madeira/actions/runs/37244573651).
Both downloaded guest metadata records and hashes matched their files and
retained the `[rpm-cas]` diagnostic marker. The ARM64EC guest DLL SHA-256 is
`36d089ca5664ea76efb0d759a716e5b68916d36ffcdefe1062a6d9618c648b76`;
the WOW64 guest DLL is
`8e38b98255dbdfc226e77e404ef711de46a748e0f4151f61f462681895783764`.
The native FEX archive SHA-256 is
`317e0929d2c496c44f941c40598e4d00f7af7d2d340f40d21224e8b003298d85`
and both configuration inline headers are present. All 59 host checks passed
in run 37244575135. Native app linking and device execution remain pending.

The app job in [run 37244570613](https://github.com/llucasandersen/Madeira/actions/runs/37244570613)
subsequently passed Xcode compilation/linking, ad-hoc signing, deep strict
codesign verification and packaging at Madeira `e6f6a2c`. The downloaded
`Madeira-diagnostic-e6f6a2c.ipa` passed `verify-diagnostic-ipa.py` with that
exact full commit, matching upstream app/helper IDs, version 0.1.3/build 100,
runtime hashes, ZIP CRC and checksum. Its SHA-256 is
`c02c67e857a9995821b3bd14b32ee71b8e846936c947b91fb7962fe8d3fc89ee`.
The provenance records Xcode 26.6 (17F113), iPhoneOS SDK 26.5, requested JIT
and increased-memory entitlements, and no extended virtual addressing. The
package needs normal re-signing before installation. This is the first
diagnostic IPA, not a device-tested final compatibility release.

It is published as
[compatibility diagnostic 1](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.1),
tagged at the exact IPA source commit. The release's four asset sizes and
server SHA-256 digests match the verified USB files: IPA, checksum,
provenance and README. The IPA was copied to
`E:\Madeira-Compatibility-Test\Madeira-diagnostic-e6f6a2c.ipa` and the package
verifier passed against that USB copy. Installation, data retention, JIT,
Memory+ and every game acceptance result remain pending phone verification.

`dxmt-arm64ec-build.yml` builds the five DXMT-owned ARM64EC graphics DLLs
with `build/dxmt-ios/build-pe.sh`, using the pinned DXMT cross file and Wine
import libraries built from the pinned Madeira Wine source. Wine import
library generation uses explicit PE targets, not the Unix runtime build.
The graphics outputs, hashes and metadata are isolated under
`build/ci-output/dxmt-arm64ec`; they are not staged into an IPA. The new clean
build must pass before this step can be considered verified. Madeira D3D12
is a separate component and is not included in these five DLL outputs.

The clean graphics build passed in
[run 37243959329](https://github.com/llucasandersen/Madeira/actions/runs/37243959329)
at Madeira `b45638b` / DXMT `8937c08c3` / Wine `f8a089569`.
All five downloaded file hashes and PE metadata records matched, with PE32+
headers, relocations and direct import filenames available in the tracked
farm. Four DLLs have the same direct import lists as their tracked
counterparts. The fifth, DXMT's `d3d9.dll`, is an alternative renderer: it
imports `winemetal.dll`, while the tracked `d3d9.dll` imports Wine's
`wined3d.dll`. It must not silently replace that existing path during source
assembly. The Wine farm selector now includes its configured `d3d9.dll`
target; the earlier selector incorrectly assigned that tracked DLL to DXMT.
A fresh Wine rebuild is required to verify the corrected selection. No new
graphics DLL has been staged into the diagnostic app or tested on the phone.

That corrected Wine rebuild passed in
[run 37244307162](https://github.com/llucasandersen/Madeira/actions/runs/37244307162)
at Madeira `1364c6a` / Wine `f8a089569`, producing 142 images with 26
excluded/unmatched entries. All downloaded file hashes and PE metadata were
verified. The rebuilt Wine `d3d9.dll` retains the tracked DLL's direct import
list (`wined3d.dll`, `ucrtbase.dll`, `kernel32.dll`, `ntdll.dll`), with SHA-256
`8342fd51f3d5a2b70c8ca2db0fcb2f6d3f904d41e8713f29e3be80861a94b108`.
Direct import filenames are available across the rebuilt Wine images and
tracked component farm. Export/API-set resolution, layout requirements and
execution remain separate gates before these files are staged.

The graphics workflow now continues with the existing
`build/madeira-d3d12/build-pe.sh`, using DXMT's freshly generated winemetal
import library. It retains the three Madeira D3D12 DLLs and three guest test
executables in a separate `Madeira-D3D12-source-build` artifact, with hashes
and PE metadata. This extension requires a new clean build; compiling the
test executables does not establish that they execute or render on the phone.
The isolated outputs are not installed over tracked app DLLs.

The extended graphics workflow passed in
[run 37244663403](https://github.com/llucasandersen/Madeira/actions/runs/37244663403)
at Madeira `3ddad3e`, building five DXMT DLLs, three Madeira D3D12 DLLs and
three guest test executables. All eleven downloaded file hashes and PE
metadata records matched, and both artifacts record the exact runner source
commit and pinned Wine/DXMT revisions. `d3d12.dll` and `madeira_d3d12.dll`
are identical, with SHA-256
`d560c447182f47cf628024930c534360597a9a52de00dcc877100b85da81eee1`;
`d3d12core.dll` has SHA-256
`7cd9a89acb96ce2e33bffde3c33293018cd50e066665ad3615eb24640c3a7d6a`.
No guest executable or graphics renderer was executed in that runner build;
device rendering, API-set/export resolution and regression gates remain.

Clean run 37233256882 compiled LLVM through its final library steps, then
failed linking LTO because LLVM 15's `HandleLLVMOptions.cmake` treated iOS
as an ELF target and added `-Wl,-z,defs`. The pinned source adjustment now
excludes iOS with Darwin in that condition, in addition to the existing
AddLLVM export/dead-strip adjustments. The clean LLVM rebuild and artifact
upload passed in [run 37235516076](https://github.com/llucasandersen/Madeira/actions/runs/37235516076)
at Madeira `a66c795`. This verifies that component; app packaging and device
installation remain pending.

The diagnostic IPA uses an ad-hoc signature carrying the requested JIT and
increased-memory-limit entitlements. It has no provisioning profile, private
signing identity or extended-virtual-addressing entitlement. Re-sign it with
your normal sideloading tool and verify Memory+ after installation. Microsoft
runtime DLLs are not supplied in this public build; see
`tools/fetch-vcruntime.md`. Unchanged PE components use the tracked upstream
binaries for this first diagnostic package; a complete source rebuild of those
components and the device acceptance tests remain required for the final
release. `build-provenance.json` records that distinction and the source/DLL
hashes for each generated IPA.

Before publishing or copying a diagnostic artifact, run the read-only package
check (Python 3.11 or newer) using the exact commit built by Actions:

```text
python tools/verify-diagnostic-ipa.py Madeira-diagnostic-<commit>.ipa --provenance build-provenance.json --checksum Madeira-diagnostic-<commit>.ipa.sha256 --expected-commit <full-built-commit>
```

It checks the IPA checksum/ZIP, upstream app and helper bundle IDs, build 100,
and the packaged ntdll/Dock hashes and diagnostic markers. macOS `codesign`
verification remains a packaging gate; this portable check does not verify
signatures or establish successful installation/gameplay on the phone.

`fex-guest-build.yml` separately rebuilds the ARM64EC Windows guest translator
from the pinned Madeira FEX fork. Its clean configuration specifies the
`arm64ec-w64-mingw32` triple and the iOS guest-host flags, including the default
MinGW CRT link path required by this fork. These flags belong to the Windows
guest module; the native iOS FEX build does not enable them. The clean guest
build passed in [run 37238119112](https://github.com/llucasandersen/Madeira/actions/runs/37238119112)
at Madeira `133c43d` / FEX `259f3ba7f`. The downloaded `xtajit64.dll` matches
its artifact SHA-256 `299114f827d5d1c8c95f996835377a9d42adcf29c6838c625b744344a436f7fb`
and has the same twelve direct import modules as the tracked translator.
Its output must be device-tested before replacing the tracked translator in a
release IPA. It does not change the current diagnostic app workflow's selected
runtime artifacts.

`wine-i386-build.yml` separately attempts the complete i386 Wine/DXMT farm
from the pinned Madeira submodules on a clean macOS runner. It retains source
revisions, module hashes and build logs, and checks the existing direct-import
closure before uploading the farm. Missing non-API-set imports now fail the
build script rather than only printing a count. API-set resolution and actual
guest execution still require device tests. The clean build passed in
[run 37239431287](https://github.com/llucasandersen/Madeira/actions/runs/37239431287)
at Madeira `f8da3ca`, Wine `f8a089569` and DXMT `8937c08c3`. The runner built
718 Wine modules plus seven DXMT outputs and reported zero missing direct
imports. The downloaded archive SHA-256 is
`613ae92c6185519e1eabc021912bd8929813cf9cddc2e35ff8f9e82527d1b959`;
all 725 module hashes were checked against the manifest and every image is
i386 PE32 (`Machine=0x014c`). Archive members were inspected without extracting
or staging them into the app. This does not replace the diagnostic IPA's PE
modules or prove guest execution.

`wine-wow64-build.yml` attempts Wine's native ARM64 `ntdll`, `wow64` and
`wow64win` DLLs in a separate `wine/build-wow64-pe` tree. It retains stripped
PE outputs, architecture/import metadata, source revisions and hashes under
`build/ci-output/wine-wow64`; it does not stage them into the app. The clean
build passed in [run 37239712754](https://github.com/llucasandersen/Madeira/actions/runs/37239712754)
at Madeira `6925786` / Wine `f8a089569`. All three downloaded hashes and PE
metadata records matched the artifact manifest. Each image is ARM64 PE32+
(`Machine=0xaa64`), with relocation data and the same direct import list and
image size as its tracked counterpart. The output hashes are:

| Module | SHA-256 |
| --- | --- |
| ntdll.dll | `c0249347083a7548affa3325b9c4adecfd11f17e27332016198f3aa43f56f9e1` |
| wow64.dll | `a4b81086cfb287e30b9c2075a5bae2f0f91686242f14b4f54f9cb7786fc0f1e7` |
| wow64win.dll | `14b1e4d801d9b3b68526b63c24e9f8b5bc2cb87b18fe534253bb7f9878cce52d` |

Import availability, loader layout/padding requirements and execution must
still be checked before packaging these outputs as replacements. In particular,
`wow64win.dll` imports `win32u.dll`, which is not part of this three-DLL artifact.

`wine-arm64ec-build.yml` attempts a clean rebuild of the tracked farm's
Wine-owned ARM64EC images with `build/wine-pe/build-farm.sh`. Selection comes
from the configured Wine file targets. It explicitly excludes the DXMT, FEX
and Madeira D3D12 replacements and records every unmatched tracked image in
`selection.json`; a same-named Wine graphics module must not replace those
components. Outputs are isolated
under `build/ci-output/wine-arm64ec`, with source revisions, hashes and PE
metadata. They are stripped compiler outputs, without the special ntdll app
padding, and are not staged in an IPA. Missing targets and import closure must
be reviewed before claiming the complete farm is reproducible.
The first run (37241759542) configured successfully but the selector treated
object-file rules as image candidates and failed on the repeated `main.o`
basename. It now filters to loadable image extensions before checking unique
targets. A retry is required; no DLL compile pass is claimed for that run.
The corrected clean rebuild passed in
[run 37241978858](https://github.com/llucasandersen/Madeira/actions/runs/37241978858)
at Madeira `9ee9399` / Wine `f8a089569`. It built 140 Wine-owned images and
recorded 27 excluded/unmatched images. Every downloaded module hash and PE
metadata record matched the artifact manifest, and every direct import list
matched its tracked counterpart. All output headers report PE32+ / `0x8664`;
that tag alone does not prove ARM64EC execution, which remains a device gate.
The build's explicit compiler target supplies the ARM64EC compile evidence.
Direct-import presence checking against the complete tracked farm found one
existing gap: `bthprops.cpl` imports `bluetoothapis.dll`, which is absent from
that farm. The same import exists in the tracked `bthprops.cpl`; this build did
not introduce it. API-set/export resolution, that gap, the other components,
ntdll padding and device execution still require review before staging a
complete source-built farm in a release.

The selector now also requires the configured `bluetoothapis.dll` target and
records its `bthprops.cpl` dependency reason in `selection.json`. The pinned
Wine sources contain both modules and declare that import in
`dlls/bthprops.cpl/Makefile.in`. The additional DLL goes into isolated build
output. The clean rebuild passed in
[run 37242977884](https://github.com/llucasandersen/Madeira/actions/runs/37242977884)
at Madeira `4903bf1` / Wine `f8a089569`, producing 141 Wine-owned images.
All downloaded hashes and PE metadata records were checked against the files.
The new `bluetoothapis.dll` SHA-256 is
`4712c58795aad0c042413e0edd7b1350ec5a1392754ce6b01eda678fb5996f3d`.
All direct import filenames are present across these rebuilt Wine images and
the tracked component farm, including this dependency. Export/API-set
resolution and execution remain unverified; the DLL is not yet staged into
the diagnostic IPA, so the installed farm's gap is still pending assembly.

`fex-wow64-build.yml` verifies the separate aarch64 Windows FEX module for
32-bit guests, with the Madeira guest-window feature enabled and a bounded
two-worker compile. The clean build passed in
[run 37238634599](https://github.com/llucasandersen/Madeira/actions/runs/37238634599)
at Madeira `3eb4186` / FEX `259f3ba7f`. The downloaded aarch64 PE `xtajit.dll`
matches its artifact SHA-256
`48f80523f08f66765b8e00ad0a85b5ccb2400cdcc82f315cdd52ea910c83686f`
and the tracked translator's direct import list. Its source revisions, PE
metadata and checksum are retained; this build does not prove device behavior
or replace the diagnostic IPA's tracked translator automatically.

This is the "scripts to control compilation and installation" record the
LGPL relink obligation depends on (docs/LICENSING.md). Each step says
whether it has been re-executed from a clean checkout. The 2026-09-16
clean-clone test at `8a8cabe` found missing native build inputs and then-local
submodule commits. Source retrieval is now fixed as described above; a fresh
checkout still lacks the inputs marked "not in the repository" below.
Steps marked UNVERIFIED have not yet been re-run from scratch.

## Inputs that are not in the repository

| Input | Why absent | How to obtain | Verified from clean |
|---|---|---|---|
| `toolchains/llvm-mingw-20260421-ucrt-macos-universal/` | 122 MB third-party toolchain | `bash build/ci/fetch-mingw.sh` downloads `llvm-mingw-20260421-ucrt-macos-universal.tar.xz` from https://github.com/mstorsjo/llvm-mingw/releases/tag/20260421, checks SHA-256 `bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7`, and extracts under `toolchains/` | clean fetch/check/extraction passed in the guest and Wine builds, including run 37239712754 |
| `toolchains/llvm-project/` + `toolchains/llvm-ios-build/` + `toolchains/llvm-host-build/` | LLVM built for iOS | `bash build/llvm-ios/build.sh` fetches upstream llvm-project commit `8dfdcc7b7bf66834a761bd8de445840ef68e4d1a`, builds host tablegen, applies the documented iOS linker guards and builds the iOS static libraries with bounded workers | clean source build and artifact upload passed in run 37235516076 |
| `research/GPTK/Metal Shader Converter 4.0 beta 2.pkg` | Apple installer, 30 MB, licence-bound | Apple developer downloads; SHA-256 `1acc33c87ea663933df89721a998d066106685473020bcbe007cee7a16155734` (pinned in `build/madeira-d3d12/deps.sh`). Only needed to REBUILD the converter fetch; the library itself is tracked | n/a |
| `app/Madeira/x86_64-vcruntime/` | Microsoft Visual C++ 2015-2022 x64 runtime DLLs (concrt140, msvcp140*, vcamp140, vccorlib140, vcruntime140*), redistributable under Microsoft's terms, not under this repository's licence | extract from Microsoft's `vc_redist.x64.exe` (or copy from `C:\Windows\System32` of a licensed Windows install) into that folder | UNVERIFIED |
| A free Apple ID; StikDebug or a pairing file plus LocalDevVPN | signing and JIT runtime requirements | see `docs/JIT.md` | n/a |

## Native build chains (all in the repository)

Run in this order after the inputs above are in place. Outputs are
git-ignored and consumed by the app project.

Statements below about verification on "the development machine" or "this
session" are historical upstream build records. They do not establish a clean
build or device pass for this compatibility fork. Explicit Actions run IDs
identify the component checks completed for this fork; the diagnostic IPA's
native runtime and app packaging are still pending.

1. `build/gnutls-ios/build.sh`: GMP 6.3.0, Nettle 3.10.1, GnuTLS 3.8.9 from
   the tracked tarballs in `build/gnutls-ios/src` (SHA256SUMS there) ->
   `app/Madeira/lib{gmp,nettle,hogweed,gnutls}.a` (these four outputs are
   also tracked). Verified: built on the development machine; not re-run
   from a clean checkout.
   `build/ffmpeg/build.sh`: FFmpeg 7.1.1 in an LGPL-only configuration (WMA,
   MPEG audio and PCM decoders; mp3/wav/mov demuxers; no H.264/HEVC/AAC),
   built from the tracked, unmodified release tarball in `build/ffmpeg/src`
   after verifying it against `build/ffmpeg/src/SHA256SUMS` -> headers in `toolchains/ffmpeg-ios/include`
   (read by `build/ntdll-unix/build.sh` for winegstreamer's unix side) and
   `app/Madeira/lib{avformat,avcodec,swresample,avutil}.a` (ignored; the app
   target links them together with VideoToolbox, CoreMedia, CoreVideo,
   AudioToolbox and CoreFoundation). The configure arguments are the ones the
   port was built and device-tested with on the WSL toolchain; the macOS form
   of the script is UNVERIFIED.
2. FEX (submodule, branch ios-port-2607):
   - `FEX/build-ios`: `build/fex-ios/build.sh` -> `FEX/build-ios/FEXCore/Source/lib{FEXCore,FEXCore_Base,JemallocLibs}.a` and the `External/{cephes,fmt,SoftFloat-3e,xxhash}` archives. Clean native build passed in run 37234579200 at Madeira `980371c` / FEX `259f3ba7f`; this does not verify the separate Windows guest translator or gameplay.
   - `FEX/build-arm64ec`: `build/fex-arm64ec/build.sh` (configures with `FEX/Data/CMake/toolchain_mingw.cmake` and the explicit iOS host/triple options on first run, builds target `arm64ecfex`, copies `Bin/libarm64ecfex.dll` to `app/Madeira/arm64ec-windows/xtajit64.dll`). Clean configure, compile and artifact checksum verified in run 37238119112; device compatibility remains pending.
3. Wine (submodule, branch madeira-lgpl):
   - unix side: `build/ntdll-unix/build.sh`, `build/wineserver/build.sh`,
     `build/win32u-unix/build.sh` -> `app/Madeira/lib{ntdll_unix,wineserver,win32u_unix}.a`. Verified on the development machine.
   - PE side: `build/wine-pe/build-ntdll.sh` (configures `wine/build-arm64ec` with `--enable-archs=arm64ec --without-x --disable-tests --enable-winegstreamer` on first run, builds `dlls/ntdll`, strips, pads to SizeOfImage + 0x50000, copies to the app). Other PE modules: `build/wine-pe/build-modules.sh <name>...` (same tree; it builds each module's DLL target `dlls/<name>/arm64ec-windows/<name>.dll`, strips it with `--strip-debug` like every shipped builtin and installs it into `app/Madeira/arm64ec-windows/`, or into `$DEST`). Building the DLL target rather than `make -C dlls/<name>` is also what winegstreamer needs (enabled by `--enable-winegstreamer` although GStreamer is absent, since its unix side is `build/ntdll-unix/winegstreamer_unixlib_ios.c`). Without arguments the script rebuilds the stock builtins added for games: `cryptsp`, `d3dx11_43`, `msvcp110`, `msvcr110` and `xaudio2_7` (committed in `app/Madeira/arm64ec-windows/` like every other builtin). It needs bison 3 for `tools/wrc` (macOS ships 2.3; Homebrew's is used when installed). The strip/pad step was verified this session; the configure step is UNVERIFIED from clean; build-modules.sh reproduced the five default DLLs at their shipped sizes on the development machine (2026-10-03).
   - `app/Madeira/arm64ec-windows/` is the DLL farm: every file in it is linked into the prefix (`system32` for x64 sessions, and `sysx64`), so a Wine module is only available if it was built and copied there. The native D3D12 path needs two stock modules in addition to the existing ones: `dcomp.dll` (`make -C dlls/dcomp`; a 64-bit Godot 4 engine loads it before it creates its D3D12 device, and gives up on D3D12 without it) and `ktmw32.dll` (`make -C dlls/ktmw32`; an optional import the same engine probes).
4. DXMT (submodule, branch ios-port):
   - unix side: `build/dxmt-ios/build.sh` (needs `toolchains/llvm-ios-build`) -> `app/Madeira/libdxmt_combined.a` (ignored; the app links it). Verified this session.
   - PE side: `meson setup dxmt/build-arm64ec dxmt -Dbuildtype=release -Dwine_build_path=../../wine/build-arm64ec --cross-file=dxmt/build-arm64ec-win.txt` then `ninja -C dxmt/build-arm64ec src/winemetal/winemetal.dll` (and d3d11.dll) -> copied to `app/Madeira/arm64ec-windows/`. Verified this session (winemetal.dll).
5. Native D3D12 runtime: `build/madeira-d3d12/build-pe.sh` -> `d3d12.dll`, `madeira_d3d12.dll` and the test executables in `app/Madeira/arm64ec-windows/` (tracked). Verified this session. `build/madeira-d3d12/fetch-converter.sh` re-verifies the converter library; `build/stage-licenses.sh` refreshes the bundled licence copies (the Xcode build fails if they are stale).
6. App: `xcodebuild -project app/Madeira.xcodeproj -scheme Madeira -destination 'generic/platform=iOS' -allowProvisioningUpdates build` (Debug is the configuration that runs the games; Release builds have crashed the guest), then zip `Payload/Madeira.app` into an IPA and sideload. Verified this session on the development machine.
7. WoW64 (32-bit programs, optional): `build/wine-i386/build.sh` (i386 Wine farm
   -> `app/Madeira/i386-windows/`), `build/fex-wow64/build.sh` (FEX WOW64 module
   -> `app/Madeira/aarch64-windows/xtajit.dll`) and the aarch64 `wow64.dll` /
   `wow64win.dll`; see docs/WOW64.md, "Building". The FEX WOW64 module's clean
   macOS-host build is verified in run 37238634599. The separate Wine i386
   farm's clean macOS build is now verified in run 37239431287; Wine's native
   wow64/wow64win source rebuild is verified in run 37239712754. Device execution
   and packaging of these new outputs remain pending.

## Status of the LGPL relink question

A recipient of a built package can obtain the complete corresponding
source of every LGPL library (Wine fork, GnuTLS, Nettle, GMP, FFmpeg) from the
repository, and the application source and build scripts above. Whether
they can actually relink depends on assembling the "not in the repository"
inputs and re-executing the UNVERIFIED steps; that end-to-end clean-machine
rebuild, signing and installation has NOT been performed. Until it is,
docs/LICENSING.md keeps the relink capability marked unverified. The
alternative the LGPL offers, shipping the application's object files, is
not currently done.
# Verified DXMT graphics artifacts in diagnostic IPAs

The diagnostic workflow accepts optional `dxmt_source_run`, a completed,
successful run of `dxmt-arm64ec-build.yml` in the same repository. It downloads
the authenticated Actions artifact and verifies its recursive Wine/DXMT pins
against the checkout, module inventory, SHA-256 hashes, PE metadata and ARM64EC
compiler provenance before staging `d3d10core.dll`, `d3d11.dll`, `dxgi.dll` and
`winemetal.dll`. The existing Wine `d3d9.dll` is preserved. The app packaging
gate verifies those same hashes inside the built app and includes the graphics
run, component pins and hashes in `build-provenance.json`. The Metal side is
still rebuilt from the pinned DXMT source in the app job. Without this optional
input, tracked graphics PE binaries remain in use.

Graphics source run 37248224379 passed with DXMT `7e2396b` and Wine `f8a08956`.
Local verification accepted its downloaded artifact and rejected a modified
DLL and a mismatched component pin. This establishes source build and staging
checks, not rendered gameplay or a Ravenfield device pass.
