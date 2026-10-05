# Game compatibility test matrix

Target device: iPhone18,2, iOS 26.6.2, Memory+ active, StikDebug JIT, no extended virtual address entitlement. Record the exact IPA SHA-256, device build, game build, Steam client file hashes, Madeira log and repeat count for each run. A blank result is not a pass.

Latest startup-crash candidate: `7257ae1`, with per-process late-alias
registrations. Full 79-check host workflow 37319437329 passed at `dd2f973`;
downloaded inventories and sanitizer logs are clean. `dd2f973` changes only
the fixture extraction from the runtime/app source at `7257ae1`. Initial
37318424980 failed that extraction and is not accepted as a full pass.
Fresh native job 111791000983 and app job 111796486469 passed in 37318428523,
including strict codesign. Local and USB package/source/identity/provenance
checks passed; the app binary contains the callback-retirement marker.

Candidate 6 is delivered at
`E:\Madeira-Compatibility-Update-6\Madeira-diagnostic-7257ae1.ipa`,
87,414,514 bytes, SHA-256
`a297b30dac9b6c899396548ab7d6c61baea1aa8e8472a91586a896f5f8a4cfe4`.
The [candidate 6 prerelease](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.6)
is for crash retesting. Candidate 5's actual phone log confirms content ready
and D3D12 device creation but startup access violations. The main-thread fault
producer and candidate-6 gameplay/relaunch remain unverified.

Previous completed host validation: all 79 checks and real Valve archives passed
at `7301473` in 37279302920. Downloaded inventories match every distinct check,
with zero raw/effective exits and no sanitizer diagnostics. This includes the
actual native control transfers, cache/record preservation and refused depot
keys, alongside all earlier native/loader/window/memory/download regressions.

Previous completed app validation: workflow 37279305970 and app job 111663398759
passed at `7301473`, including strict macOS codesign verification. The package
reuses the unchanged native runtime verified at `889c6be` in 37274760178.
Local and USB ZIP/CRC/identity/runtime/graphics/source-stamp/checksum checks
passed. The IPA is 87,414,822 bytes, SHA-256
`b894ed3bce43fcb03f5cdb34dd55c6743913d8102c4d6e62349932284a69bd15`.
This adds the owned native control, read-only cache handling, immediate
background cancellation and installed-game access to candidate 4. No new
physical gameplay, throughput or complete native peer shutdown proof is inferred.

Earlier source work at `4c0d431` adds the owned-depot phone native-control
measurement and a 79th actual-source host check. Targeted 37278109635, full
host 37278126945 and app 37278129844 passed. Downloaded host inventories match
all 79 distinct checks with zero raw/effective exits and no sanitizer diagnostics;
the native control fixture observed 72 successful requests and peak concurrency
eight. No package from this source was delivered: the follow-up at `7301473`
disables retained manifest-cache publication, cancels directly on background
entry and exposes the controls for installed owned games. Full host 37279302920
and app 37279305970 passed for that source. The app reuses the unchanged
verified native runtime from 37274760178. The superseded intermediate app runs
37278775828 and 37279072888 were requested to cancel after real source changes;
cancellation is not an app-build pass. USB candidate 5 was the previous
verified delivered package; the new phone crash export and candidate 6 supersede
its pending Teardown test request.

The cache-preservation follow-up at `e0f8dda` passed all 79 checks and real Valve
archives in 37278773557. Downloaded inventories match that source with zero
raw/effective exits and no sanitizer diagnostics. The actual owned-library
ASan harness reports cache and install-record preservation and refused-key
enforcement for the new control method. This proof predates the later background
observer and installed-game menu changes, which passed their complete gates
above. Physical checks remain required.

Earlier completed host validation: all 78 checks and real Valve archives passed
at `889c6be` (37274755529). Downloaded inventories match that full test tree,
with no missing or duplicate checks. This includes native exit records,
callback delivery, exact selected-game/host generation correlation and stale
file-tail delivery, synchronized image-owner publication and scalar Mach LSE
alias atomics and native ARM paired stores, alongside the existing sanitizer
fixtures, explicit Mach FP/LR/SP scalar writeback/pre-index cases and the
runner's recovering-sanitizer integration. Every raw and
effective exit is zero, with no sanitizer diagnostics. Fresh native compilation
at `889c6be` passed in job 111649257006 of workflow 37274760178, including the
scalar register/pre-index follow-up. Its app job 111652524468 also passed;
physical device acceptance remains unverified.

Earlier completed app validation: workflow 37274760178 passed at `889c6be`,
including app job 111652524468 and strict macOS codesign verification. It uses
the fresh native runtime from the same workflow and source commit above.
Local ZIP/CRC/identity/runtime/graphics/source-stamp checks passed, SHA-256
`8600b07540c57783e61777ac63086a7a30e63706cf0e6a9209d96128ebf58670`.
The IPA is 87,374,598 bytes, includes native launch/exit correlation, image
ownership synchronization, scalar Mach LSE atomics, integer paired stores
and the explicit scalar register/pre-index follow-up,
and has no new physical
acceptance results. Automatic renderer selection, 10-minute/relaunch behavior,
repeated map loads and final delivery remain unverified.

The later Mach LSE alias change at `5d10bb3` passed its targeted ASan/UBSan and
TSan checks (37269300151), full 76-check suite and fresh native compilation.
Its app/package gates passed (37269302622). The subsequent integer paired-store
change at `343028f` passed corrected native ARM ASan/UBSan and TSan fixtures
at `17776be` (37271658156), with terminal logs checked for sanitizer errors.
The initial fixture's recovering UBSan result is not accepted. Full 77-check
suite 37271658528 passed with exact inventories and clean native ARM logs;
fresh iOS workflow 37271515195 passed. `17776be`
changes only tests/docs from the runtime/app sources built at `343028f`.
No new device result
or final USB delivery is inferred from these builds.

Earlier completed source validation: all 73 distinct checks and real Valve
archives passed at `e0835ca` (37261593279). Fresh native socket changes compiled
at `4503b36` (37261069251); complete app/package/signing gates at `e0835ca`
passed (37261594883). Local package checks passed, SHA-256
`b034dbf2409aef16360a7f51af6a2c7f764c7422eec2eb1760ab85294f73bf2e`.
The new automatic Teardown profile uses the supplied registry schema; its
74-check/app gates and physical renderer/10-minute/relaunch acceptance remain
pending. This is not a final release or a new USB delivery.

Earlier source validation: all 68 distinct host checks passed at `a5669ae`
(run 37253512089); its Xcode/IPA build passed (run 37253514108). The downloaded
package passed ZIP, identity, runtime and graphics provenance checks, SHA-256
`c02e208064f6d41ad3014cad7146600df6d6449893f00aa9b158ff97676a8288`.
This locally retained diagnostic has no new device acceptance results and
does not replace the delivered USB update 2 or constitute the final release.

At `4666116`, all 69 distinct host checks passed in run 37255530422. The
downloaded Linux/macOS inventories matched every repository check without
omissions or duplicates. This includes the actual Wine machine gate, coherent
fresh-install runtime pins, AMD64 header guard, launch-stage deadlines and
loader rejection parsing. Its IPA run 37255532583 passed Xcode/Metal/package
gates; local ZIP, identity, runtime and graphics provenance verification passed
for `Madeira-diagnostic-4666116.ipa` (87,305,193 bytes), SHA-256
`d206888d0da7b6f8915c38fe3491634bc3ab3faf5cb439677995a1f652a2174f`.
That local diagnostic predates automatic existing-runtime upgrades and the
real-archive CI gate introduced at `4acba7a`. It supplies no new device result
and has not replaced USB update 2. The later upgrade requires its own gates.

| Target | Required device result | Current evidence | Status |
| --- | --- | --- | --- |
| PEAK, app 3527290 | Steam stays alive; PEAK.exe created; menu, single-player level, DX11/DXMT, audio, input, authentication and repeated launches | User reports PEAK worked and believes it is fully playable; USB transfer now includes PEAK session logs; exact installed build and individual acceptance results pending | Gameplay success reported; detailed acceptance pending |
| Teardown, app 1167630 | Automatic D3D12 selection; menu, level, ten minutes of play, close and relaunch | October 5 candidate-5 log confirms required content ready, normal Valve-client game creation and D3D12 device creation; startup then faults in late cryptnet alias dispatch and separately on the main thread | Startup crash confirmed; per-emulator alias fix under build/test |
| Ravenfield | Three consecutive match loads and scene changes below the device memory ceiling | Supplied session log reaches physical footprint 6141 MB; no three-match survival result on the updated package | Memory pressure confirmed; updated device acceptance pending |
| Bomber Crew | Visible primary window from Steam; switching, fullscreen and relaunch | Reported zero size and off-screen Unity window; no new device run | Not tested on this fork |
| Steam downloader | Median throughput at least 70% of direct same-CDN `URLSession` control when CPU is not limiting; resume and corruption checks | User reports much faster Steam downloading; no measured device/native-control comparison | Improvement reported; benchmark pending |
| Existing working games | Representative Steam, D3D9, D3D11, D3D12, 32-bit and 64-bit smoke and regression runs | Selection pending | Not tested on this fork |

Host tests and a source build are separate gates. They do not stand in for the device results above.

## Original-scope completion audit, October 5, 2026

This audit retains all eleven original requirements. Candidate 6 is a tested
build for collecting missing evidence; it does not establish completion.

| Original requirement | Current authoritative evidence | Remaining gate |
| --- | --- | --- |
| 1. PEAK and Valve runtime | Coherent Valve runtime upgrade, actual PE machine/dependency fixtures, real archive checks, native/app builds and user report of earlier gameplay | Exact updated-package log; Steam survival, executable creation, single-player, audio/input, authentication, networking where supported and repeated launches |
| 2. Teardown renderer/content/children | Candidate-5 phone log confirms owned required content ready, normal Steam launch and D3D12 device creation; startup crash is now confirmed, with per-emulator alias repair in source | Resolve startup crash, then menu, level, ten minutes and relaunch on the updated package; native peer-thread resource lifetime remains under audit |
| 3. Ravenfield memory | Consumed learned JIT budgeting, measured footprint/headroom and source-built completed-resource ring trimming; host fixtures and graphics/app build | Three consecutive matches, scene changes, safe measured memory headroom and performance on the target phone |
| 4. Bomber Crew windows | Compiled owner-thread primary-window repair, startup grace and actual-source sanitizer fixtures preserving dialogs and later minimization | Real Steam start, visible game window, switching, fullscreen/windowed transitions and relaunch |
| 5. Steam downloads | Production adaptive concurrency, connection reuse/CDN selection, network/decode/write/hash/CPU/resume instrumentation, integrity fixtures and owned native-control measurement in candidate 5 | Measured same-CDN native-control comparison, roughly 70% median target when CPU is not limiting and actual device resume/update behavior |
| 6. General compatibility profiles/review | Default generic path, user opt-out and consumed Teardown profile; documented upstream report/source comparison and generic native store fixes | Device validation of consumed policy; exclusive-store reservations and unrelated reported secondary-launcher failures remain separate unresolved findings |
| 7. Steam robustness/UI | Coherent runtime dependencies, exact optional-helper gate, bounded launch stages and generation-correlated game/Steam-host creation/exit diagnostics, compiled Swift/native fixtures | Device proof that the client and optional-component/helper paths preserve launch; new logs must establish exact failure/stage attribution if a run fails |
| 8. Target iPhone/address/JIT correctness | Preserved address-map architecture; package requests JIT/Memory+ and has no extended-VA entitlement; native ARM and iOS compilation | Re-signed installation and actual iPhone18,2/iOS 26.6.2 execution, StikDebug JIT, measured memory behavior and exception delivery |
| 9. Regression/component gates | Exact 79-check Linux/Apple inventories at dd2f973, raw/effective exits zero, no sanitizer diagnostics; source-identical native repair freshly built and app/package gates passed at 7257ae1 | Representative previously working games, actual target-device regressions and any further changed subsystem gates |
| 10. Fork/docs/build/IPA | Preserved fork/submodule histories, licenses, clean worktree, documented clean build, verified package with no private signing identity, exact-source GitHub prerelease and checksum-verified USB copy | Final acceptance report and final release after the remaining required results; diagnostic publication is not final acceptance |
| 11. Definition of done | Source, host/component build, test package, prerelease and USB candidate gates have evidence | All game/device/benchmark results above and final release; overall completion is unproven |

The October 5 USB crash export is stamped `7301473` on iPhone18,2/iOS 26.6.2.
It verifies JIT/Memory+, required-content completion, Valve-client game creation
and D3D12 device creation, followed by startup access violations. It is failure
evidence, not gameplay acceptance. The native-control JSON and other physical
gates remain pending. New results must be tied to the exact source/checksum.

## Historical component build verification

At Madeira `9d2c6d3`, all 66 distinct host checks passed in
[run 37252063633](https://github.com/llucasandersen/Madeira/actions/runs/37252063633).
The downloaded inventories match all checks at that commit, including the
production ring-pressure and callback-owner diagnostic sanitizer probes.
The corrected graphics source build passed
[run 37252061524](https://github.com/llucasandersen/Madeira/actions/runs/37252061524),
with DXMT `b286373`. The callback diagnostic compiled in the native runtime
job of run 37251963677. The later learned-JIT pool sizing and headroom refresh
at `bb180ec` require their new 67-check run and native/app gates; those are
pending. These changes are absent from the delivered USB update 2, and no
new game/device acceptance pass is inferred.

At Madeira `e6e9b2311b09a187e503dd69968b9f177f5de56c`, all 64 distinct host
checks passed in [run 37250480384](https://github.com/llucasandersen/Madeira/actions/runs/37250480384).
Downloaded Linux/macOS inventories match every repository `check-*.py`,
without missing or duplicate results and with every exit code zero. This
includes the corrected shared-installer install/uninstall fixture, exact
required-depot selection, missing-manifest refusal and the production window
repair sanitizer tests. Earlier failed fixture runs remain failed.

The native runtime containing the primary-window repair compiled successfully
in [run 37249781579](https://github.com/llucasandersen/Madeira/actions/runs/37249781579).
The matching latest app compiled and packaged successfully in
[run 37250535597](https://github.com/llucasandersen/Madeira/actions/runs/37250535597),
including macOS ad-hoc codesign verification. It includes the required Steam
content preparation, paused-download resume, source-built DXMT memory policy,
window repair and measured headroom overlay. Device acceptance remains pending;
adaptive JIT sizing and broader resource reclamation are still unfinished.

## Diagnostic package delivery

Test candidate 5 is copied to
`E:\Madeira-Compatibility-Update-5\Madeira-diagnostic-7301473.ipa`, with checksum,
source/graphics provenance and installation/test instructions. The USB copy
passed the package verifier with the exact source commit and checksum above.
The [candidate 5 prerelease](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.5)
is published at exact source commit `7301473`. All five remote asset sizes and
server SHA-256 digests match the USB files; draft=false and prerelease=true were
verified through the GitHub API. The updated Teardown log and native control
JSON were requested for this package. Private USB logs remain dated October 4;
the complete goal/final release and remaining runtime findings are not resolved
by this delivery.

Test candidate 4 is copied to
`E:\Madeira-Compatibility-Update-4\Madeira-diagnostic-889c6be.ipa`, with checksum,
source/graphics provenance and installation/test instructions. The USB copy
passed the package verifier with the exact source commit and checksum above.
This is the latest package for new phone tests; candidate 3 predates the scalar
register/writeback/pre-index follow-up. The app/helper identities and update
signing requirements are unchanged. The full goal is not complete: device
acceptance, measured download comparison and remaining native lifetime findings
still require evidence and work.
The [candidate 4 prerelease](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.4)
is published at exact source commit `889c6be`. Its five remote asset sizes and
server SHA-256 digests match the USB files; draft=false and prerelease=true
were checked through the GitHub API. Teardown acceptance was requested against
this specific package. The supplied logs remain dated October 4.

Test candidate 3 is copied to
`E:\Madeira-Compatibility-Update-3\Madeira-diagnostic-3e94179.ipa`, with checksum,
source/graphics provenance and installation/test instructions. The USB copy
passed the package verifier with exact source commit and checksum above. It
contains the coherent runtime repair, automatic Teardown renderer profile,
learned JIT and staging trim policies, and the subsequent native ownership,
exit correlation and store fixes missing from update 2. It retains the existing
app identity for updating with the same signing account/App ID prefix.
New phone logs have been requested for Teardown's content preparation,
ten-minute gameplay and relaunch. This is an acceptance-test candidate;
the complete goal and final release remain pending the device gates.
The [candidate 3 prerelease](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.3)
is published at exact source commit `3e94179`. All five uploaded asset sizes
and server SHA-256 digests match the USB IPA, checksum, provenance, graphics
metadata and README; the release is a published prerelease rather than a draft.

Update 2 packages `Madeira-diagnostic-e6e9b23.ipa` from the verified source
commit above. Local package checks and the copy at
`E:\Madeira-Compatibility-Update-2` passed ZIP CRC, bundle/helper identity,
runtime hashes, graphics source pins/hashes and SHA-256 checks. Its SHA-256 is
`d323b016a6239a34cbb6182bf288c7a8d05170eb49fbedd6b96434373215c92e`.
Version 0.1.3/build 100 and the upstream bundle identity are retained for
re-signing over an existing installation with the same account/App ID prefix.
The original USB diagnostic and supplied user logs are preserved. This package
is ready for sideloading and device tests; it does not complete the full goal.

[Diagnostic release 1](https://github.com/llucasandersen/Madeira/releases/tag/v0.1.3-compat-diagnostic.1)
contains `Madeira-diagnostic-e6f6a2c.ipa`, version 0.1.3/build 100, from
Madeira `e6f6a2c`. The package identity/checksum/runtime checks passed,
including verification of the USB copy at `E:\Madeira-Compatibility-Test`.
Its SHA-256 is
`c02c67e857a9995821b3bd14b32ee71b8e846936c947b91fb7962fe8d3fc89ee`.
The CI build passed Xcode linking and macOS codesign verification. Phone
gameplay subsequently received the user report below; the exact installed
IPA and a complete successful PEAK launch log remain to be confirmed.

## User device report, October 4, 2026 (America/Chicago)

After diagnostic delivery, the user reported that PEAK worked, then clarified:
"yes fully playable I believe also downloading speed is much faster on steam too".
This records reported playable gameplay and a perceived download improvement.
Audio, controls, single-player mode, repeat launches and networking were not
confirmed individually. No diagnostic log, installed IPA checksum or measured
throughput accompanied the report. It does not establish why the earlier SDL3
failure cleared or whether the downloader meets the native-control target.

The user subsequently reported: "teardown works flawlessly super good okay so
teardown works now". This records reported successful Teardown gameplay.
The renderer, installed IPA/game build, ten-minute run and close/relaunch were
not confirmed individually, and no successful log accompanied the report.
The earlier OpenGL and dispatcher symptoms are no longer the latest device
result; their root cause and the reason they cleared remain unverified.

The user then clarified that Teardown ran once but subsequent launches remain
at the required-content message. The supplied October 4 log shows successful
online authentication, requested-app entitlement/listing, launch refusal 17
and three retries without a game process. No successful renderer evidence is
present in this failing run. The later USB log transfer supplied Steam's
content log: it explicitly names required app 228980 as not ready, and records
the dependency from depot 228989 to Teardown. Its earlier game log records a
Madeira D3D12 device being created. This establishes the dependency behind the
relaunch refusal and earlier backend initialization, not a ten-minute/relaunch
pass. Ravenfield's supplied run reaches physical footprint `fpMB=6141`; no
three-match survival result is established.

## Host regression evidence

On Madeira `980371c`, [Linux run 37234581507](https://github.com/llucasandersen/Madeira/actions/runs/37234581507)
ran all 59 existing host checks: 56 passed and three failed on missing host
modules. `check-jit-network.py` requires Swift Darwin;
`check-steam-cloud.py` requires Swift CryptoKit; `check-steam-library.py`
requires Python 3.14's `compression` package.
These failures establish an unsuitable test environment, not passing results.
Mac run 37235072729 passed the JIT network and Steam Cloud checks, but exposed
that the Steam library harness provides Linux compression/crypto shims which
conflict with the Apple SDK. The updated workflow runs the two Apple checks
on macOS and the remaining 57 on Linux, using Python 3.14 for both. The
complete combined result passed in
[run 37235206418](https://github.com/llucasandersen/Madeira/actions/runs/37235206418)
at Madeira `2e4dd32`: 57 Linux checks and two macOS checks, all exit zero.
The downloaded result artifacts were compared to every `check-*.py` in the
repository: 59 distinct checks, with no missing or duplicate entries.
The Steam library/depot harness compiled production download code and ran its
install, interruption/resume, update, corruption, ownership, shared-depot,
uninstall and refusal phases under AddressSanitizer. This establishes host
regression coverage; it supplies no real CDN/device throughput measurement.

After the decoder stage/retry timing change, all 59 checks passed again in
[run 37236100223](https://github.com/llucasandersen/Madeira/actions/runs/37236100223)
at Madeira `c76fd42`. Both downloaded result inventories were checked against
the repository's complete host check list. The known decoder vectors use the
measured pipeline; checksum rejection, corruption recovery, interruption,
resume and update behavior remain covered by the production-code harness.

After the native diagnostic counter and compile-failure gate change, all 59
checks passed in
[run 37242309362](https://github.com/llucasandersen/Madeira/actions/runs/37242309362)
at Madeira `a793ece`. The downloaded Linux and macOS result artifacts again
matched all 59 repository checks, without duplicates or missing entries.
These host results do not validate the native iOS compile or phone gameplay.

After guarding FEX's rpmalloc snapshot diagnostic with the allocator option,
all 59 host checks passed in
[run 37244575135](https://github.com/llucasandersen/Madeira/actions/runs/37244575135)
at Madeira `e6f6a2c` / FEX `b28076559`. The downloaded Linux/macOS inventories
again matched all 59 distinct repository checks, all exit zero.
