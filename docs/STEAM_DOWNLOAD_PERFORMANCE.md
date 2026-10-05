# Steam download performance

## Phone native control measurement

The source adds **Download speed measurement** to a Steam game's download
sheet. Long-press an owned game's library card and choose **Download options**
to reach it even when that game is already installed. With Steam signed in and
no game/download running, **Measure native
download speed** obtains a depot key and manifest through the existing owned
content path and makes three direct URLSession control trials against one CDN
host. A suitable sample contains 16–64 MiB of distinct encrypted chunks, at
most 256 requests and eight concurrent transfers. Each response goes to a
temporary file that is removed after measurement; no game file, install record
or journal is modified. The control includes URLSession temporary-file I/O but
excludes Steam decrypt, decompress, hash, assembly and manifest preparation.
It uses a separate ephemeral session with caching disabled and reuses
connections across trials. A byte-size mismatch, non-200 response, host change,
failed request or cancellation rejects the result; there is no retry/rotation
inside a trial that could silently change its host or workload.

Keep the app open. Cancelling, backgrounding or starting a game cancels the
measurement. Downloads queue while it runs; required-content preparation and
Dock handoff cancel and await it. Successful results overwrite the numeric-only
`madeira-control.json` in Madeira's Documents folder. Copy that file together
with the install trial logs and run the report with `--control`. The control's
log records app/depot, hostname, bytes, times and concurrency; it excludes URLs,
tokens and headers. Compare only equivalent workloads on the same phone,
network and CDN hostname. The fixed eight-transfer control measures the
response path; it is not a full install or an arbitrary Internet speed test.

The new actual-source HTTP fixture covers three trials, bounded concurrency,
invalid samples, HTTP/length refusal, cancellation and numeric JSON. Targeted
workflow 37278109635 passed at `4c0d431`; terminal Apple job 111659611983
records 72 successful sample requests and observed peak concurrency eight.
The byte-size check follows the manifest compressed-length contract also used
by [SteamKit's CDN client](https://github.com/SteamRE/SteamKit/blob/master/SteamKit2/SteamKit2/Steam/CDN/Client.cs).
Full 79-check gate 37278126945 and app workflow 37278129844 also passed at
`4c0d431`; downloaded test inventories/statuses and sanitizer logs were checked.
The follow-up cache/background/installed-game access source at `7301473` passed
full host 37279302920 and app 37279305970. Downloaded inventories and package
verification passed; the verified candidate-5 IPA is on the USB and GitHub.
Actual phone
measurement remains pending.
Delivered candidate 4 predates this feature; candidate 5 includes it. No throughput result is inferred
from the implementation or fixture.

A follow-up review found that a downloader reused after installation retains
its `depotCache` path. The control's manifest fetch now explicitly disables
custom-executable cache publication; ordinary installs retain it. The owned
library harness reuses a populated downloader, removes the fixture cache file,
checks that the control does not recreate it or change the appmanifest, restores
the fixture, and verifies depot-key refusal. Full 79-check workflow 37278773557
passed at `e0f8dda`; downloaded inventories/statuses and sanitizer logs are clean,
and the actual owned-library harness has the cache/record/refused-key PASS record.
The later background/menu source passed the complete gates above;
the earlier targeted transfer proof alone does not cover this cache behavior.

Background entry now cancels the control directly before the install-only grace
handler. The grace handler requires an active/queued download and would not
otherwise run for an isolated control measurement. The owned-library gate
checks this observer wiring; updated app compilation passed. A physical
background cancellation check remains required.

## Process CPU, resume checks and whole-install intervals

The downloader now samples `getrusage(RUSAGE_SELF)` user plus system CPU time
at the start/end of each depot's chunk phase and the whole install. Logs expose
`process-cpu-seconds` and `process-cpu-cores` (CPU seconds divided by interval
wall seconds). Average cores can exceed one; this is the entire Madeira
process, including other concurrent work, not CPU attribution to a specific
chunk or a percentage of all hardware cores. Unavailable counters are labeled
`process-cpu=unavailable`. The adaptive concurrency policy still uses its
measured decode/write load proxy; CPU reporting does not change scheduling.

On-disk reuse now reports `resume-checks`, `resume-hits`,
`resume-checked-bytes`, `resume-check-sum` and `resume-sha1-sum`. The overall
check includes open/read/buffer preparation, SHA-1 comparison and close; the
SHA-1 duration is a substage, so the two durations must not be added together.
They overlap across chunk tasks just like the network/decode sums. SHA-1
verification and manifest offsets are unchanged. Journal-skipped chunks do not
perform a new on-disk check. Failed/incomplete tasks may not return their stage
measurements, while the process CPU interval includes their actual CPU work.

`[steam-install] timing` covers server/key/manifest preparation, journals/files,
chunks and final record creation, even when an install fails (`completed=0`).
Its byte count is fetched payload returned by completed chunk tasks, including
their retry responses. It is not total observed network traffic for aborted
tasks or useful installed bytes. Successful whole-install payload throughput
is distinct from the existing depot chunk-phase throughput.

`tools/depot-benchmark-report.py` reports CPU/resume data and the separate
whole-install measurements while accepting older logs. It excludes incomplete
trials from rate medians when terminal install summaries are present; a failed
partial install must not masquerade as a successful throughput benchmark.
`check-depot-process-cpu.py` runs the production CPU sampler against the real
OS counter and validates old/new, unavailable and malformed benchmark records.
The existing production depot harness checks measured update reuse and the
full-install/CPU records while retaining its HTTP request, byte-integrity,
corruption, resume and ownership assertions. All 68 host checks passed at
`a5669ae` in run 37253512089, including the real OS CPU sampler, benchmark
parser and production depot integrity/resume harness. Xcode/IPA run
37253514108 also passed. No new device/native-control throughput result is
claimed; average process cores do not establish download-only CPU cost.

## Baseline and measurement

The delivered `e6f6a2c` baseline schedules up to eight chunks per depot with a shared
ephemeral `URLSession` and up to eight connections per host. It writes each
verified chunk with `pwrite` at the manifest offset, journals completed chunks,
and resumes an interrupted install. Network requests are therefore already
concurrent. A qualitative device improvement has since been reported, but
there is no measured throughput baseline. The adaptive source change below
requires separate build and device verification.

Each completed depot now emits one `[steam-depot] timing` line. `fetched-bytes`
counts downloaded payload bytes, including responses retried after decode or
checksum failures, excluding journaled or locally verified chunks. HTTP errors
that the download helper throws do not return a payload to this counter.
`wall` is monotonic elapsed time for that depot's
chunk phase; `MiBps` is fetched bytes divided by wall. `network-sum`,
`decode-sum`, and `write-sum` add the durations of chunk attempts, including
failed attempts before eventual success. `decrypt-sum`, `decompress-sum` and
`checksum-sum` split the decode pipeline into its three stages. The checksum
stage measures the existing Adler-32 validation; local resume verification's
SHA-1 time is not included. A stage records elapsed time even when it throws.
Those sums overlap across parallel tasks and need not add up to `wall`.
`hosts` counts successful chunks per hostname; authentication query strings
are never logged. `retries` counts failed attempts before successful chunks.
Failures that ultimately abort the depot remain visible in the existing
per-attempt trace but have no completion line. This is a first measurement
point. The later URLSession extension below adds connection setup and
time-to-first-byte; local resume SHA-1 time and CPU load remain unmeasured.
Build attempts dispatched before this extension use the earlier
aggregate timing; match the source commit to the log
fields when comparing measurements.

## Device benchmark protocol

1. On the same phone, network and Steam account, record the iOS version,
   available space, selected app and depot IDs, and whether the install is
   fresh or resumed. Keep credentials and CDN authorization strings out of
   the report.
2. Download a large owned game with Madeira. Save the progress timeline,
   `[steam-depot] timing` lines, failure traces, and iOS memory/CPU sample.
   Repeat three times after removing only that game's downloaded content and
   journal. Record CDN hosts, average and median `MiBps`, retries and the
   network/decode/write sums for each depot.
3. Measure a direct native `URLSession` control transfer from a comparable
   Steam CDN response on the same network and phone. Use an authorized public
   object or a chunk for which the account has authorization; redact its
   token. Record response bytes and wall time. Do not use the control to
   bypass Steam ownership or alter game files.
4. Compare the medians. The target is roughly 70% of the control median when
   CPU and decode are not limiting. Use the stage timings and host failures
   before changing concurrency or server rotation. Re-run interrupted resume,
   update, corruption and ownership tests after any downloader change.

No measured phone/native-control benchmark has been supplied. The user reported
faster downloads; that qualitative observation is recorded below and does not
establish a measured speedup or the control-median target.

## Measurement report tool

Use `python tools/depot-benchmark-report.py trial-1.txt trial-2.txt trial-3.txt`
to summarize the recorded timings. Supply one log containing one install trial
per file, with the same workload and fresh/resumed state across trials. Repeated
depot IDs are rejected so multiple installs cannot silently become one trial.
Fully resumed depots with no fetched bytes are excluded from network samples.
The tool accepts both the original aggregate timing and the later stage split.

For an optional control comparison, add `--control control.json`. The file is
a JSON array of native URLSession response measurements, for example:

```json
[{"bytes": 104857600, "seconds": 10.0},
 {"bytes": 104857600, "seconds": 11.0},
 {"bytes": 104857600, "seconds": 9.5}]
```

These example numbers are illustrative, not measured results. Record actual
response bytes and elapsed seconds from the same phone/network/CDN before
using the comparison. The report calculates each trial's rate from bytes and
summed depot chunk-phase wall time, then compares median rates with the 70%
target. It does not trust the rounded `MiBps` field, run the control transfer,
or establish a speed improvement by itself. Payload includes retried responses,
so a high payload rate with corruption/retries does not prove useful installed
throughput. Manifest acquisition, resume checks, finalization and failed depots
are outside this completion metric; retain the progress timeline and failure
report for the full install comparison. Stage sums overlap across chunks.

The tool reads files without modifying game content and emits selected numeric
fields only, excluding raw log lines, CDN URLs and authorization strings. It
does not replace the device benchmark or the missing URLSession transaction
instrumentation described above.

The decoder timing extension passed the complete 59-check host suite in
[run 37236100223](https://github.com/llucasandersen/Madeira/actions/runs/37236100223)
at `c76fd42`, including the production depot/decoder harness under
AddressSanitizer. This verifies host regression behavior, not phone throughput.

## URLSession transaction extension

Following diagnostic delivery, the user reported on October 4, 2026
(America/Chicago) that Steam downloading was much faster. This is a qualitative
device observation; rates, trial conditions and the exact installed IPA have
not been supplied. No measured speedup or native-control target is claimed.

The source now attaches a shared, locked per-depot metrics delegate to chunk
requests through Apple's
[`data(from:delegate:)`](https://developer.apple.com/documentation/foundation/urlsession/data(from:delegate:)).
It retains only numeric measurements and hostnames, never full request URLs,
headers or CDN authorization fragments. Each depot reports request completion
and metrics callback counts, plus observed peak active requests and chunks.
Host summaries include transaction/status/protocol counts, connection reuse,
response body bytes, DNS, connection, TLS and first-response-byte durations.

Durations are summed per host and include the number of usable samples.
`unavailable` denotes no sample, including TLS on HTTP or connection setup on
reused connections; it does not assert that setup took zero time. These
fields come from
[`URLSessionTaskTransactionMetrics`](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics).
TTFB is measured from `fetchStartDate` to `responseStartDate`, including setup.
Connection/TLS/TTFB intervals can overlap, so they must not be added as
disjoint work. Host timing covers observed callbacks for chunk HTTP attempts,
including HTTP errors and retries, and is emitted on depot failure as well as
success. Manifests and authorization requests are outside this measurement.
Compare callback counts with requests before assuming complete coverage on
any Foundation backend.

The new macOS fixture uses the production HTTP helper and delegate against a
delayed localhost server, with both success and HTTP-error responses. The full
host suite now has 60 checks: the existing 59 plus this Apple metrics fixture.
The Apple fixture passed in run 37245983985: three completed requests had
three callbacks, two reused connections, and 0.414 seconds of summed TTFB
against the delayed HTTP server. The entire 60-check host run and iOS
diagnostic build 37245986232 succeeded at `22b4341`. Both downloaded host
inventories exactly matched all 60 distinct checks, with no missing,
duplicate or failing entries. The downloaded IPA passed the package verifier
(checksum, ZIP CRC, app/helper identity and runtime provenance): SHA-256
`db202ce0d0a2356c18e1a98868b9ed9d27fbd702a99d4f2fc141831f3ebd1bc3`.
It is retained locally, with the published/USB diagnostic unchanged.
This extension is not in
the already delivered `e6f6a2c` diagnostic IPA. CPU load, resume SHA-1 timing,
a measured native control benchmark remain required.

## Adaptive chunk scheduling

The next source revision replaces the fixed eight-task batch with a per-depot
controller starting at eight and bounded between two and sixteen chunks.
The shared URLSession permits up to sixteen HTTP connections per host; HTTP/2
can multiplex requests. Completion-driven scheduling retains the same chunk
validation, pwrite offsets, journal and cancellation behavior. Lowering the
limit drains existing tasks before issuing replacements; it does not cancel
successful work. Resumed chunks do not feed the controller.

Each observation window requires at least two seconds and a full batch of
downloaded chunks. Useful compressed bytes per wall second exclude retried
payload. Retry pressure halves the limit; processing time exceeding network
time lowers it by two. These stage durations are load proxies, not CPU
utilization. Otherwise, the controller probes two extra tasks and retains them
only with at least five percent throughput gain. Failed probes restore the
previous limit. Reductions wait two observation windows before probing again.
Decisions emit numeric limits and fixed reasons, without authorization data.

This policy needs device tuning: network variability can affect a probe,
and old tasks drain during a reduced window. Its deterministic regression
check covers gain, plateau, bounds, retry/processing pressure, cooldown,
resumed chunks and invalid clocks. The existing production install harness
remains the gate for concurrent file assembly, resume, corruption and updates.
All 61 host checks passed in run 37246614671 at `8ad72d0`, including the
compiled controller test and production depot harness under AddressSanitizer.
Downloaded inventories matched all 61 distinct checks with no failures.
The iOS app built and packaged in run 37246616477. Its downloaded IPA passed
the package verifier, SHA-256
`6b0d48c8a43745b4823eebb1ed2f4ed06175cca13af95d72e734d4373f92ca41`.
No measured device speed improvement is attributed to this policy, and it is
absent from the published/USB `e6f6a2c` diagnostic, which remains unchanged.

## Measured CDN selection and retry routing

Source inspection found that retries re-sorted hosts by failure count but
selected the next host by attempt index. With two hosts, failure of A changed
the order from A,B to B,A; attempt 1 then selected A again. The new retry
selection excludes hosts already tried by this chunk until all alternatives
have been visited. Attempts remain bounded at five; cancellation, authorization
and content validation retain their existing behavior.

Validated chunk responses now feed a locked per-install throughput estimate:
encrypted response bytes divided by the successful HTTP request's wall time,
including connection setup and first byte latency. An exponential average
uses 25% of the new observation. Decode/write time and unsuccessful/corrupt
payloads do not feed this estimate. Failure counts take precedence over rates.
Unsampled healthy hosts receive initial trials; then the fastest measured host
is preferred, with one in eight selections rotating among the healthiest peers
so slower or recovered servers can be reassessed. An already-tried host is
still excluded on a chunk retry, even when an exploration selection picks it.

The compiled policy test covers the A,B retry scenario, exhaustive alternatives,
empty sets, negative seeds, invalid samples, throughput preference, continued
exploration, failure demotion, changed rates and concurrent access. The full
production depot harness remains required for ownership, encryption, corruption,
file assembly, resume and update regressions. CI and device benchmarking for
this extension are pending. Ranking individual responses can be affected by
chunk size and shared bandwidth; no device speedup is inferred from it.

The first Apple test run at `390540e` exposed a fixture extraction defect:
the metrics test used the CDN class's documentation comment as its end marker.
Updating that comment caused the fixture to include the unrelated class and
fail on its missing SteamLog dependency. The test now ends at the next class
declaration. The gate remained failed until this correction; a fresh full
host run is required.

The corrected full host run 37247281022 passed at `68e4bce`. Both downloaded
inventories matched all 61 distinct checks, including measured CDN selection,
concurrent health access and the production depot harness. The CDN app source
also built and packaged in run 37247108050 at `390540e`; its downloaded IPA
passed package verification with SHA-256
`0e41aa4e8d8a8be5c0432a59ff7122875bd50a73a8ecc0024815ef816b7d8927`.
That local package is separate from the first diagnostic release/USB copy.
Device performance and the native-control benchmark remain pending.
