# Changelog

## Unreleased

- Repair late DLL alias delivery when another pseudo-process registers its emulator. Preserve private copies and sub-floor ownership, bound registrations and serialize borrowed callbacks with retirement. All 79 host checks passed at dd2f973 (corrected fixture only); fresh native/app/package gates passed at 7257ae1. USB test candidate 6 is verified. Candidate 5's phone log confirms content ready and D3D12 creation followed by startup faults; the main-thread producer and new gameplay/relaunch acceptance remain pending.

- Verify all 79 host checks, real Valve archives and app packaging at `7301473`, including the owned native control follow-ups. Local, USB candidate-5 and public prerelease asset/source/checksum verification passed; physical acceptance and remaining runtime findings keep the complete goal and final release unfinished.

- Expose Download options from an owned game's library-card context menu so the native control is reachable for installed games as well as uninstalled ones. Full host/app verification remains pending.

- Cancel native control measurements directly on app background entry, before download-only grace handling. The measurement must not depend on an active install for cancellation; updated host/app gates are pending.

- Disable custom-executable manifest cache publication during native control measurements after an earlier install. Preserve the install default and extend the actual owned-library harness with cache/record preservation and refused-key checks; updated gates are pending.

- Add an owned-depot native URLSession control measurement to the Steam download sheet, with three bounded trials, cancellation/handoff serialization and numeric JSON export. Add actual-source HTTP refusal/concurrency/cancellation coverage; new 79-check and app gates remain pending. Candidate 4 predates this feature.

- Verify fresh native and app packaging at `889c6be` in workflow 37274760178, including strict macOS codesign verification. Downloaded and USB candidate-4 IPA checks passed; physical acceptance and the final release remain pending.

- Verify all 78 host checks and real Valve archives at `889c6be` in 37274755529, including explicit Mach scalar register/pre-index regressions. Downloaded inventories have zero raw/effective exits and no sanitizer diagnostics; fresh native/app packaging remains pending.

- Verify expanded actual ARM scalar/pair fixtures under ASan/UBSan and TSan at `889c6be` in 37274755701. The earlier scalar pre-index regression correctly failed at `91a7a92`; full host/native/app gates and updated packaging remain pending.

- Correct FP/LR store sources and FP/LR/SP indexed base writeback in older Mach alias-store paths. Use explicit Darwin register fields and unsigned address arithmetic; extend the real ARM fixture with actual scalar decoder branches and boundary cases. New native/full gates are pending; candidate 3 predates this follow-up.

- Verify all 78 host checks and real Valve archives at `3e94179`, fresh paired-store native compilation at `343028f`, and the complete source-stamped `3e94179` app package. Local and USB test-candidate package verification passed; device acceptance and final release remain pending.

- Refuse green host CI results when a recovering sanitizer reports an error with subprocess exit zero. Preserve the raw status and output, and add actual runner integration coverage; updated 78-check CI is pending.

- Verify all 77 host checks and real Valve archives at `17776be` in 37271658528, including corrected native ARM pair-store fixtures. Downloaded inventories and sanitizer logs passed; fresh iOS, physical acceptance and final delivery remain pending.

- Correct the native pair fixture's pointer arithmetic and make sanitizer recovery fatal. Verified two clean actual ARM passes under ASan/UBSan and TSan at `17776be` in 37271658156; full 77-check and fresh iOS gates remain pending.

- Decode indexed and offset integer STP/STNP through complete writable aliases, including the reported CoreCLR opcode. Preserve native pair atomicity, either-half fault handling and base writeback; add a real ARM/LSE2 Mac regression with guard pages and competing native pair operations. Full 77-check/native/app gates and device acceptance remain pending.

- Verify all 76 host checks and real Valve archives at `5d10bb3`, including actual Mach LSE operation/alias/concurrency fixtures under both sanitizers, fresh native iOS compilation and the complete app package. Local source-stamp/runtime/graphics/identity/checksum verification passed; subsequent paired-store gates, physical acceptance and final delivery remain pending.

- Verify all 75 host checks, real Valve archives, fresh native runtime and complete `7ab72cb` IPA, including synchronized image ownership. Local source-stamp, runtime, graphics, identity and checksum checks passed. Subsequent Mach LSE gates, physical acceptance and final delivery remain pending.

- Handle scalar LSE atomic writes through complete writable aliases in the Mach exception path, including the reported HotSpot `LDADDAL` opcode. Preserve atomic ordering, zero/FP/LR register semantics, unchanged refusal and Mono SWP capture; add actual-source operation/bounds/concurrency sanitizer fixtures. Full 76-check/native/app gates and device acceptance are pending.

- Verify all 75 distinct host checks and real Valve archives at `0546f2d`, fresh native exit diagnostics at `5ed9a2e`, and the complete source-stamped `0546f2d` IPA. Record current upstream compatibility-report/source comparisons. Subsequent image-owner publication gates, device acceptance and final USB delivery remain pending.

- Synchronize fixed-image owner/death publication with image commit and retirement using the existing leaf mutex. Refuse takeover of a bound occupant and snapshot diagnostics before unlocking; extend actual ownership/concurrency sanitizer fixtures. Fresh native/full gates remain pending.

- Correlate native selected-game and embedded Steam-host exits by Windows PID and immutable child birth generation. Preserve raw Windows status before Unix conversion, distinguish reported host faults from other exits, and deliver rare lifecycle events while gameplay file tailing is paused. Add actual C and production Swift regressions; fresh host/native/app gates are pending.
- Verify the fresh `b9c3219` native/app IPA in workflow 37264684593 and its local source-stamp, runtime, graphics, identity and checksum gates. Its 75-check host gate passed; physical acceptance and final delivery remain pending.

- Complete all 75 host checks and real Valve archive checks at `b9c3219`, including delayed worker capture and stable socket generation. Verify the source-stamped `9a9156c` app package against its provenance and 75-check source-equivalent baseline. New native/app gates and physical acceptance remain pending.
- Capture a worker's original socket record in its creator before pthread scheduling, then adopt it in the native startup wrapper. Preserve existing thread-creation cleanup and test delayed startup across PEB reuse plus allocation/pthread failures; fresh native/full gates are pending.
- Retain each native Wine thread's original child socket record across PEB address reuse. Bind new workers before server initialization and explicitly bind child boot registration; old peers retain their retired descriptor/exit flag and cannot tear down a successor. Extend actual-descriptor generation/sanitizer coverage; new native/full gates and complete resource quiescence remain pending.
- Verify all 75 distinct host checks at `7d57beb`, including corrected incomplete-XML refusal and executable-owner sanitizer fixtures; the fresh native runtime at `4f954eb` compiled successfully. Current app/source-stamp package gates and device acceptance remain pending.
- Stamp each packaged diagnostic's exact source commit into the existing build label before signing, and verify it against provenance during packaging/release checks. Phone logs can distinguish diagnostics that share the preserved app/helper version 100.
- Bind fixed-base executable readiness to the retired image's owner and generation. Prevent unrelated child cleanup from publishing another image's address for reuse before its translation cleanup. Snapshot readiness log fields under the mutex; add actual-retirement sanitizer/concurrent-owner fixtures. Fresh native/75-check/app gates and complete thread quiescence remain pending.
- Add a consumed, versioned compatibility profile catalog and per-library-entry opt-out. Teardown's adapter selects D3D12 through its supplied registry schema, preserves other settings byte for byte, backs up original settings and refuses unknown or ambiguous formats. Generic games retain their ordinary path; new 74-check/app gates and device renderer selection are pending.
- Verify all 73 host checks and the real Valve archive gate at `e0835ca`, fresh native socket-ownership compilation at `4503b36`, and the complete `e0835ca` IPA. Local package identity, runtime, source pins and checksums passed. Generation/quiescence, physical acceptance and final delivery remain pending.
- Replace the overflowing 64-entry child socket registry with stable mutex-protected owner records. Retain retired identities, claim teardown once and prevent unknown child owners from falling through to the parent socket. Add real-descriptor saturation/duplicate-exit/concurrency sanitizer fixtures; new native/73-check gates and generation/quiescence audit are pending.
- Complete the 72-check host and app build gates at `af27470`, including selected executable startup evidence and exact UTF-16 identity matching. Physical acceptance and final delivery remain pending.

- Match server-confirmed process creation to the complete executable path selected from Steam launch metadata. Add a distinct startup creation stage and windowless timeout message, preserving generic observations when the image is unknown. Extend the real parser/state/contract fixtures; full host/app and device gates are pending.

- Emit a bounded machine-readable Windows process creation record only after the server confirms successful `NtCreateUserProcess`. Preserve Unicode image identity without command lines; add formatter sanitizer and publication-order fixtures. Fresh native/72-check gates and UI lifecycle integration are pending.
- Verify all 71 host checks and the real Valve archive gate at `08c3862`; the fresh child-spawn cleanup runtime and complete app build passed. Physical acceptance and final delivery remain pending.

- Reject failed startup descriptor duplication before creating an iOS pseudo-process, and release duplicated descriptors after failed thread creation. Preserve parent descriptors and successful child ownership. Add real-descriptor failure-injection and repeated-launch sanitizer fixtures; fresh native and 71-check gates are pending.

- Capture Wine's final DLL dependency-resolution status in startup diagnostics, including the supplied SDL3 `0xC000007B` record. Preserve architecture evidence in the full log and avoid treating optional failures as fatal. Extend the production parser fixtures; new host/app gates are pending.
- Verify all 70 host checks, actual Valve archives and the fresh native runtime at `959e37c`, including exact-basename optional-helper containment. App packaging and device acceptance remain pending.

- Pin the coherent supported Valve AMD64 Steam runtime with SDL3 and FFmpeg dependencies. Add automatic verified January-runtime upgrades before Dock launch, old-file backups, complete publication preflight, atomic file writes and interrupted-upgrade recovery. Preserve unknown files and game/account data. Add filesystem regression coverage and actual Valve archive validation to CI; new gates and device acceptance are pending.

- Verify all 68 host checks and the Xcode/Metal/IPA gates at `a5669ae`, including process CPU/resume profiling, JIT policy, report lifecycle integration, ring reclamation and callback diagnostics. Downloaded package identity/runtime/graphics hashes passed. Device acceptance and the final release remain pending; USB update 2 is preserved.

- Report measured process CPU time/average cores per depot and whole install, and separate on-disk resume check/SHA-1 timing and bytes. Extend the benchmark reader with whole-install summaries and incomplete-trial exclusion; preserve downloader integrity and scheduling. Host/app gates and device measurements are pending.
- Add per-Steam-build learned JIT pool sizing with conservative frontier telemetry, two sufficiently long rendered sessions, growth margin, explicit override precedence and persisted interruption fallback. Unknown builds retain their standard pool. Native/host/app and repeated-map device verification are pending. Refresh measured overlay headroom every 250 ms.
- Correct the callback dispatcher diagnostic to compare the selected dispatcher with the calling thread's registered ntdll. The supplied Teardown warning classified a child as a session thread using a mutable global PEB. Preserve real mismatch detection and the existing dispatch path; sanitizer/native gates are pending.
- Add measured-headroom reclamation of completed DXMT upload/copy/argument ring buffers and refresh the initializer's completion fence before idle reclamation. Preserve unfinished GPU resources, the newest working block and normal healthy-memory lifetime. Sanitizer and source-build verification are pending; this is absent from delivered update 2.
- Build compatibility update 2 at `e6e9b23`: all 64 host checks and Xcode/package signing gates passed. Add verified required Steam shared-installer preparation, paused-download resume, primary-window repair, adaptive downloader/CDN selection, source-built DXMT mip pressure policy and measured memory headroom. Device acceptance and adaptive JIT/general resource reclamation remain incomplete.
- Publish the verified first diagnostic IPA as `v0.1.3-compat-diagnostic.1` and copy it with its checksum, provenance and instructions to the requested USB. Preserve the original Madeira app/helper IDs and use build 100 for an in-place update with the same signing identity. Phone installation and gameplay remain pending.
- Guard FEX's optional rpmalloc snapshot diagnostic with the allocator build option. Native Apple builds disable rpmalloc; guest builds retain the diagnostic. Native linking, both guest builds and all 59 host checks passed.
- Retain FEX's generated inline configuration headers in CI artifacts and generate DXMT's three AIR helper headers before standalone iOS compilation. The corrected FEX artifact and native DXMT compile passed; complete IPA packaging is pending.
- Add isolated source builds for Wine ARM64EC, ARM64 WOW64, Wine/DXMT i386, both FEX guest modules and DXMT graphics. Preserve Wine's tracked D3D9 renderer and rebuild its missing Bluetooth dependency. Component evidence and remaining device gates are recorded in `docs/BUILDING.md`.
- Separate Steam chunk decryption, decompression and checksum timing, and include failed-attempt stage time and retried payload bytes in completed-depot measurements. Throughput improvement remains unmeasured.
- Restrict FEX's Windows memory-region query to Windows builds while retaining native misaligned CASPAL diagnostics.
- Guard FEX's iOS guest-runtime telemetry reads in native builds to match the condition on their declarations. The clean macOS build exposed undeclared counters in `Core.cpp`; the ARM64EC guest path retains its existing instrumentation.
- Add a macOS diagnostic IPA build workflow and remove the prebuilt archive requirement from full Wine server and DXMT Unix builds. The first diagnostic compilation and packaging passed on clean runners using verified component artifacts; device verification remains pending.
- Add per-depot Steam chunk stage timing and a device throughput measurement protocol. No speed improvement is claimed yet.
- Add ARM64EC PE loader stage diagnostics to the pinned Wine fork to locate the Steam SDL3 invalid-image rejection in a device log. This does not yet resolve that failure.
- Preserve Steam's numbered launch entry through the native library and Madeira Dock so games without entry 0 can be submitted to Valve's client with their selected Windows entry. Host and device verification status is recorded in `docs/COMPATIBILITY_OVERHAUL.md`.
- Add a read-only PE import inspector and initial compatibility evidence and test matrix.
