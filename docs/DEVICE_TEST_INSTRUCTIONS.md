# Diagnostic iPhone test

First diagnostic: **`Madeira-diagnostic-e6f6a2c.ipa`**, version 0.1.3, build 100.
The SHA-256 is
`c02c67e857a9995821b3bd14b32ee71b8e846936c947b91fb7962fe8d3fc89ee`.
Keep the matching `build-provenance.json` and checksum beside the IPA.

This package is for collecting evidence on iPhone 17 Pro Max / iOS 26.6.2.
It includes the numbered Steam launch-option fix, ARM64EC PE rejection-stage
logging and initial depot timing. The four target games have not yet passed
their acceptance tests on this fork.

## Install and first test

1. Use the `Madeira-diagnostic-<commit>.ipa` beside this file with your usual
   SideStore, AltStore or Sideloadly setup. The package carries an ad-hoc
   signature and needs to be re-signed to install. Use your existing signing
   account and app identity when updating an existing Madeira installation.
   **Install over the existing app; do not delete Madeira first.** This fork
   retains upstream's bundle ID `com.willfaust.madeora` (including that spelling)
   and packages build 100. If your sideloading tool changed the installed bundle
   ID, reuse that exact ID and the same signing account/App ID prefix. A new ID
   installs a separate app; a mismatched signing prefix can reject an update.
   If installation reports an identity mismatch, keep the existing app and
   send the error. An update should retain its data, but device verification
   remains pending. See [Apple's installation troubleshooting](https://developer.apple.com/library/archive/technotes/tn2319/_index.html).
2. Open Madeira and verify that Memory+ is active. Enable JIT through
   StikDebug as usual. The build does not request extended virtual addressing.
3. Start **PEAK (3527290)** from the Steam library with **Madeira Dock**.
   Record whether Steam remains alive, whether the game appears, and how long
   the attempt takes. If it starts, test the menu, a single-player level,
   sound, controls and a second launch.
4. Open **Files → On My iPhone → Madeira**. Share `madeira-log.txt` from that
   attempt. If Madeira crashed and was reopened, share
   `madeira-log.prev.txt` too. The `logs` folder also retains named session
   logs. Send the full log so the loader error and surrounding dependency
   attempts can be read together.
5. Include the IPA filename, iOS version, Memory+ status, game result and the
   `build-provenance.json` supplied with the IPA. Logs should contain
   `[pe-image]` if the invalid-image failure reaches an instrumented PE loader
   stage. Absence of that marker is useful evidence too.

The public diagnostic build supplies Wine's builtins but does not bundle
Microsoft Visual C++ runtime DLLs. See `tools/fetch-vcruntime.md` in the source
repository if your installation needs Microsoft's runtime.

## Subsequent tests

After the PEAK evidence is reviewed, test Teardown, Ravenfield and Bomber Crew
using the same IPA and send one log per game. Teardown needs a level and ten
minutes of play; Ravenfield needs three consecutive normal match loads;
Bomber Crew needs window visibility, transitions and a relaunch. Record each
result, including failures. These results will guide the next source changes.

For a download test, record the app ID, download size, elapsed time and whether
it was fresh or resumed. The log now contains one `[steam-depot] timing` line
per completed depot. A network speed test alone is not a Steam CDN control
measurement; the full measurement procedure is in
`docs/STEAM_DOWNLOAD_PERFORMANCE.md`.

Source: https://github.com/llucasandersen/Madeira
