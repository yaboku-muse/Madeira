// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Jfishin, 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Derived from Jfishin's Madeira Steam client, used in Madeira with the
// author's permission (see docs/STEAM_SIGNIN.md, "Provenance"). Substantially
// rewritten by 125hz for the owned library and downloads (docs/STEAM_LIBRARY.md).

import Foundation
import zlib
import CommonCrypto
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Progress for one application install, across all of its depots.
struct SteamDownloadProgress: Equatable, Sendable {
    enum Phase: String, Sendable { case preparing, downloading, finishing }
    var phase: Phase = .preparing
    /// Compressed bytes to fetch for the whole install (all selected depots).
    var totalBytes: UInt64 = 0
    /// Compressed bytes already on disk, including chunks resumed from a
    /// previous attempt.
    var doneBytes: UInt64 = 0
    var bytesPerSecond: Double = 0

    var fraction: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : 0 }
}

/// Orchestrates downloading an owned application's Windows depots from the
/// Steam content network into a Steam library folder.
///
/// Follows Steam's content protocol: the account's depot key and the
/// manifest request code come from the CM connection, which issues them only
/// to an account that owns the depot; manifests and chunks come from content
/// servers over HTTPS. Nothing here alters the downloaded files.
///
/// Behaviour:
/// - All manifests are fetched first, so progress covers the whole install.
/// - Completed chunks are journaled per depot manifest; a cancelled, failed or
///   interrupted install resumes without re-fetching them.
/// - Files are sized to their manifest length, so an update that shrinks a
///   file cannot leave stale trailing bytes.
/// - Chunk writes happen on the download tasks with pwrite, never on the
///   main actor; a dedicated URLSession keeps chunks out of the URL cache.
/// - Manifest paths are validated to stay inside the install folder, and
///   directory names are folded case-insensitively (Windows semantics on a
///   case-sensitive iOS volume).
/// - Each chunk retries on other content servers before the install fails.
@MainActor
final class DepotDownloader {
    private let session: SteamCMSession
    private var depotKeys: [UInt32: Data] = [:]
    private var cdnAuthTokens: [String: String] = [:]  // "depot|host" -> "?auth=…" fragment
    private let attemptsPerChunk = 5
    private let hostPoolSize = 6

    private nonisolated static let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: config)
    }()

    /// Replaces the content server directory (host tests only): the servers
    /// to fetch from, as `https://host` or `http://host:port` URLs.
    var contentHosts: ((_ appID: UInt32) async throws -> [String])?

    init(session: SteamCMSession) {
        self.session = session
    }

    // MARK: - Public API

    /// Read-only control measurement using an owned depot's authorized chunks.
    /// Key/manifest authorization remains the same as installation. No install
    /// folder, journal or appmanifest is opened or written.
    func nativeControl(_ app: SteamAppInfo) async throws -> [ContentControlTrial] {
        let hosts: [String]
        if let provider = contentHosts { hosts = try await provider(app.appID) }
        else { hosts = try await contentServers(appID: app.appID) }
        guard let host = hosts.first else { throw SteamError.chunkDownloadFailed("No content servers are available.") }
        for depot in app.installDepots() {
            try Task.checkCancellation()
            guard let gid = depot.publicManifestID else { continue }
            let key = try await depotKey(depotID: depot.depotID, appID: app.appID)
            let contentApp = !app.freeToDownload ? (depot.fromApp ?? app.appID) : app.appID
            let manifest = try await fetchManifest(depotID: depot.depotID, appID: contentApp,
                manifestGID: gid, key: key, hosts: [host], cacheCustomExecutables: false)
            let auth = await cdnAuthFragment(depotID: depot.depotID, appID: contentApp, host: host)
            var requests: [ContentControlRequest] = []
            var bytes: UInt64 = 0
            var seen = Set<Data>()
            sample: for file in manifest.files {
                for chunk in file.chunks where chunk.compressedSize > 0 && seen.insert(chunk.sha).inserted {
                    if requests.count == 256 || bytes == 64 * 1024 * 1024 { break sample }
                    let size = UInt64(chunk.compressedSize)
                    guard size <= 8 * 1024 * 1024 else { continue }
                    guard bytes + size <= 64 * 1024 * 1024, requests.count < 256 else { continue }
                    guard let url = URL(string: "\(host)/depot/\(depot.depotID)/chunk/\(chunk.shaHex)\(auth)") else {
                        throw SteamError.chunkDownloadFailed("Invalid content URL.")
                    }
                    requests.append(ContentControlRequest(url: url, bytes: size))
                    bytes += size
                }
            }
            guard bytes >= 16 * 1024 * 1024 else { continue }
            let hostname = URL(string: host)?.host ?? "unavailable"
            SteamLog.event("[steam-control] begin app=\(app.appID) depot=\(depot.depotID) host=\(hostname) chunks=\(requests.count) bytes-per-trial=\(bytes) trials=3 concurrency=8")
            let results = try await ContentControl.run(requests)
            for (index, trial) in results.enumerated() {
                SteamLog.event(String(format: "[steam-control] timing app=%u depot=%u host=%@ trial=%d completed=1 bytes=%llu seconds=%.6f MiBps=%.3f",
                    app.appID, depot.depotID, hostname, index + 1, trial.bytes, trial.seconds,
                    Double(trial.bytes) / trial.seconds / 1048576))
            }
            return results
        }
        throw SteamError.chunkDownloadFailed("This game's depots do not have a suitable 16 MiB control sample.")
    }

    /// Download an app into `steamApps/common/<installdir>` and write its
    /// appmanifest. Returns the install folder. Throws CancellationError when
    /// the calling task is cancelled; completed chunks stay journaled.
    func install(_ app: SteamAppInfo, steamApps: URL,
                 mergeExistingOwnerRecord: Bool = false,
                 ownedDepots: @escaping () async -> Set<UInt32>? = { nil },
                 progress report: @escaping (SteamDownloadProgress) -> Void) async throws -> URL {
        let installStarted = ProcessInfo.processInfo.systemUptime
        let installCPU = ContentProcessCPUInterval()
        var totalFetchedBytes: UInt64 = 0
        var completed = false
        defer {
            let wall = max(0.001, ProcessInfo.processInfo.systemUptime - installStarted)
            SteamLog.event(String(format: "[steam-install] timing app=%u completed=%d fetched-bytes=%llu wall=%.3fs payload-MiBps=%.3f %@",
                app.appID, completed ? 1 : 0, totalFetchedBytes, wall,
                Double(totalFetchedBytes) / wall / 1048576, installCPU.report(wall: wall)))
        }
        let depots = app.installDepots()
        guard !depots.isEmpty else { throw SteamError.depotNotFound(app.appID) }
        // Before the key requests, so a refused depot still has its selection logged.
        SteamLog.event("[steam-depot] selection app=\(app.appID) build=\(app.buildID) \(app.depotSelectionSummary())")

        let folderName = SteamInstallFiles.safeFolderName(app.installDir.isEmpty ? "app_\(app.appID)" : app.installDir)
        let installURL = steamApps.appendingPathComponent("common", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        let journalDir = steamApps.appendingPathComponent("downloading", isDirectory: true)
            .appendingPathComponent("\(app.appID)", isDirectory: true)
        try FileManager.default.createDirectory(at: installURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)

        var state = SteamDownloadProgress()
        report(state)

        depotCache = steamApps.appendingPathComponent("depotcache", isDirectory: true)
        let hosts: [String]
        if let provider = contentHosts { hosts = try await provider(app.appID) } else { hosts = try await contentServers(appID: app.appID) }
        guard !hosts.isEmpty else { throw SteamError.chunkDownloadFailed("No content servers are available.") }

        // 1. Keys, manifests and per-host authorization for every depot.
        let health = ContentHostHealth()
        let pool = Array(hosts.prefix(hostPoolSize))
        var plans: [DepotPlan] = []
        var licenseSkipped: [UInt32] = []
        // The logged-on account, for the install record. Read while the session
        // is connected: it idles out during a long download.
        var accountID: UInt64 = 0
        for depot in depots {
            try Task.checkCancellation()
            guard let gid = depot.publicManifestID else { continue }
            let key: Data
            do {
                key = try await depotKey(depotID: depot.depotID, appID: app.appID)
            } catch SteamError.depotKeyNotFound(let refused) {
                // A depot Steam refuses AND the account's licenses do not
                // include is content this account does not own (another
                // edition, extra content): it is left out. Any other refusal
                // still fails.
                if let owned = await ownedDepots(), !owned.isEmpty, !owned.contains(refused) {
                    licenseSkipped.append(refused)
                    continue
                }
                throw SteamError.depotKeyNotFound(refused)
            }
            if session.steamID != 0 { accountID = session.steamID }
            let contentAppID = !app.freeToDownload ? (depot.fromApp ?? app.appID) : app.appID
            let manifest = try await fetchManifest(depotID: depot.depotID, appID: contentAppID,
                                                   manifestGID: gid, key: key, hosts: hosts)
            var auth: [String: String] = [:]
            for host in pool {
                auth[host] = await cdnAuthFragment(depotID: depot.depotID, appID: contentAppID, host: host)
            }
            plans.append(DepotPlan(depotID: depot.depotID, manifestGID: gid, key: key, manifest: manifest,
                                   hosts: pool, auth: auth,
                                   declaredSize: depot.publicSizeBytes, health: health))
        }
        if !licenseSkipped.isEmpty {
            SteamLog.event("[steam-depot] license app=\(app.appID) skipped=\(licenseSkipped.map(String.init).joined(separator: ",")) kept=\(plans.map { String($0.depotID) }.joined(separator: ","))")
        }
        guard !plans.isEmpty else {
            if let refused = licenseSkipped.first { throw SteamError.depotKeyNotFound(refused) }
            throw SteamError.depotNotFound(app.appID)
        }

        // 2. Prepare files and load journals off the main actor.
        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepare(plans: plans, installURL: installURL, journalDir: journalDir)
        }.value
        state.totalBytes = prepared.totalBytes
        state.doneBytes = prepared.doneBytes
        state.phase = .downloading
        report(state)
        SteamLog.event("[steam-depot] install begin app=\(app.appID) depots=\(plans.count) files=\(prepared.fileCount) resume=\(prepared.doneBytes > 0 ? 1 : 0)")

        let remaining = prepared.remainingUncompressed
        if remaining > 0 {
            let values = try? installURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? Int64.max))
            if available < remaining { throw SteamError.insufficientDiskSpace(needed: remaining, available: available) }
        }

        // 3. Chunks.
        let started = Date()
        let resumedBytes = state.doneBytes
        var lastReport = Date.distantPast
        for (index, plan) in plans.enumerated() {
            let journal = try JournalWriter(url: prepared.journals[index])
            defer { journal.close() }
            let work = prepared.pending[index]
            let paths = prepared.paths[index]
            let existing = prepared.existing[index]
            let attempts = attemptsPerChunk
            let depotStarted = ProcessInfo.processInfo.systemUptime
            let depotCPU = ContentProcessCPUInterval()
            var concurrency = ContentConcurrency(started: depotStarted)
            defer {
                for line in plan.networkMetrics.report(depotID: plan.depotID) { SteamLog.event(line) }
            }
            var timing = ChunkTiming()
            var fetchedChunks = 0
            var hostsUsed: [String: Int] = [:]
            try await withThrowingTaskGroup(of: (UInt64, UInt64, ChunkTiming).self) { group in
                var next = 0
                var active = 0
                func enqueue() {
                    guard next < work.count else { return }
                    let item = work[next]; next += 1
                    active += 1
                    let chunk = plan.manifest.files[item.file].chunks[item.chunk]
                    let path = paths[item.file]
                    let verify = existing[item.file]
                    group.addTask {
                        var local = ChunkTiming()
                        if verify, Self.chunkAlreadyPresent(chunk, path: path, timing: &local) {
                            return (item.key, UInt64(chunk.compressedSize), local)
                        }
                        var measured = try await Self.fetchChunk(chunk, plan: plan, path: path,
                                                                 attempts: attempts, seed: item.file &+ item.chunk)
                        measured.resumeCheck = local.resumeCheck
                        measured.resumeChecksum = local.resumeChecksum
                        measured.resumeChecks = local.resumeChecks
                        measured.resumeHits = local.resumeHits
                        measured.resumeCheckedBytes = local.resumeCheckedBytes
                        return (item.key, UInt64(chunk.compressedSize), measured)
                    }
                }
                while active < concurrency.limit && next < work.count { enqueue() }
                for try await (key, bytes, chunkTiming) in group {
                    active -= 1
                    journal.append(key)
                    state.doneBytes += bytes
                    timing.resumeCheck += chunkTiming.resumeCheck
                    timing.resumeChecksum += chunkTiming.resumeChecksum
                    timing.resumeChecks += chunkTiming.resumeChecks
                    timing.resumeHits += chunkTiming.resumeHits
                    timing.resumeCheckedBytes += chunkTiming.resumeCheckedBytes
                    if chunkTiming.fetchedBytes > 0 {
                        totalFetchedBytes += chunkTiming.fetchedBytes
                        fetchedChunks += 1
                        timing.fetchedBytes += chunkTiming.fetchedBytes
                        timing.network += chunkTiming.network
                        timing.decode += chunkTiming.decode
                        timing.decrypt += chunkTiming.decrypt
                        timing.decompress += chunkTiming.decompress
                        timing.checksum += chunkTiming.checksum
                        timing.write += chunkTiming.write
                        timing.retries += chunkTiming.retries
                        hostsUsed[chunkTiming.host, default: 0] += 1
                        if let change = concurrency.observe(now: ProcessInfo.processInfo.systemUptime,
                                                            bytes: bytes, network: chunkTiming.network,
                                                            processing: chunkTiming.decode + chunkTiming.write,
                                                            retries: chunkTiming.retries) {
                            SteamLog.event("[steam-depot] concurrency depot=\(plan.depotID) limit=\(concurrency.limit) reason=\(change)")
                        }
                    }
                    let now = Date()
                    if now.timeIntervalSince(lastReport) >= 0.25 {
                        lastReport = now
                        let elapsed = now.timeIntervalSince(started)
                        if elapsed > 1 { state.bytesPerSecond = Double(state.doneBytes - resumedBytes) / elapsed }
                        report(state)
                    }
                    // A decrease drains existing tasks; it never cancels a valid
                    // chunk or discards its write/journal result.
                    while active < concurrency.limit && next < work.count { enqueue() }
                }
            }
            let wall = max(0.001, ProcessInfo.processInfo.systemUptime - depotStarted)
            let mibPerSecond = Double(timing.fetchedBytes) / wall / 1_048_576
            let hostSummary = hostsUsed.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: ",")
            SteamLog.event(String(format: "[steam-depot] timing depot=%u fetched-chunks=%d fetched-bytes=%llu wall=%.2fs network-sum=%.2fs decode-sum=%.2fs decrypt-sum=%.2fs decompress-sum=%.2fs checksum-sum=%.2fs write-sum=%.2fs retries=%d MiBps=%.2f hosts=%@ concurrency-limit=%d resume-checks=%d resume-hits=%d resume-checked-bytes=%llu resume-check-sum=%.6fs resume-sha1-sum=%.6fs %@",
                                  plan.depotID, fetchedChunks, timing.fetchedBytes, wall,
                                  timing.network, timing.decode, timing.decrypt, timing.decompress,
                                  timing.checksum, timing.write, timing.retries,
                                  mibPerSecond, hostSummary, concurrency.peak,
                                  timing.resumeChecks, timing.resumeHits, timing.resumeCheckedBytes,
                                  timing.resumeCheck, timing.resumeChecksum, depotCPU.report(wall: wall)))
        }

        // 4. Install record. Sizes come from the manifests; no tree walk.
        state.phase = .finishing
        report(state)
        let installed = plans.map { plan in
            AppManifestWriter.InstalledDepot(depotID: Int(plan.depotID), manifestGID: plan.manifestGID,
                                             size: Int64(plan.manifest.totalUncompressedSize))
        }
        // Depots taken from another app are that app's content. Valve's client
        // refuses a launch until the owner app has its own record, so both
        // records are written the way the client writes them.
        var owners: [UInt32: UInt32] = [:]
        for depot in depots { if let from = depot.fromApp, from != app.appID { owners[depot.depotID] = from } }
        let own = installed.filter { owners[UInt32($0.depotID)] == nil }
        let shared = installed.filter { owners[UInt32($0.depotID)] != nil }
        // Files Valve's client must customize per user before they run, as
        // Windows-style install-relative paths for the record's CheckGuid block.
        let custom = plans.flatMap { plan in
            plan.manifest.files.filter { $0.flags & DepotManifest.customExecutableFlag != 0 && !$0.isDirectory }
                .map { $0.filename.replacingOccurrences(of: "/", with: "\\") }
        }
        if !custom.isEmpty { SteamLog.event("[steam-record] custom-executables app=\(app.appID) custom=\(custom.count)") }
        if mergeExistingOwnerRecord {
            guard shared.isEmpty, custom.isEmpty else {
                throw SteamFileError.invalid("Unsupported nested or customized shared installer content.")
            }
            try AppManifestWriter.mergeOwnerManifest(ownerAppID: app.appID, ownerName: app.name,
                ownerBuildID: app.buildID, installDir: folderName, steamID: accountID,
                steamAppsPath: steamApps.path, depots: own)
        } else {
        try AppManifestWriter.writeManifest(
            appID: app.appID, name: app.name, installDir: folderName, buildID: app.buildID,
            steamID: accountID, sizeOnDisk: prepared.totalUncompressed,
            steamAppsPath: steamApps.path, installedDepots: own,
            sharedDepots: shared.map { ($0.depotID, Int(owners[UInt32($0.depotID)]!)) },
            customExecutables: custom)
        }
        if !shared.isEmpty {
            var written = 0, skipped = 0
            for ownerID in Set(owners.values).sorted() {
                let depots = shared.filter { owners[UInt32($0.depotID)] == ownerID }
                guard !depots.isEmpty else { continue }
                // Only when the owner installs to this same folder, where the files are.
                guard let owner = app.sharedOwners[ownerID],
                      SteamInstallFiles.safeFolderName(owner.installDir).caseInsensitiveCompare(folderName) == .orderedSame else {
                    skipped += 1; continue
                }
                try AppManifestWriter.mergeOwnerManifest(ownerAppID: ownerID, ownerName: owner.name, ownerBuildID: owner.buildID,
                                                         installDir: folderName,
                                                         steamID: accountID, steamAppsPath: steamApps.path,
                                                         depots: depots)
                written += 1
            }
            SteamLog.event("[steam-shared-record] app=\(app.appID) shared=\(shared.count) owners-written=\(written) owners-skipped=\(skipped)")
        }
        try? FileManager.default.removeItem(at: journalDir)
        SteamLog.event("[steam-depot] install complete app=\(app.appID) bytes=\(prepared.totalUncompressed) seconds=\(Int(Date().timeIntervalSince(started)))")
        completed = true
        return installURL
    }

    /// Whether a previous attempt left resumable progress for this app.
    static func hasPartialDownload(appID: UInt32, steamApps: URL) -> Bool {
        let dir = steamApps.appendingPathComponent("downloading/\(appID)", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0.hasSuffix(".journal") }
    }

    // MARK: - Plan

    struct DepotPlan: Sendable {
        let depotID: UInt32
        let manifestGID: UInt64
        let key: Data
        let manifest: DepotManifest
        let hosts: [String]
        let auth: [String: String]
        let declaredSize: UInt64
        let health: ContentHostHealth
        let networkMetrics = ContentNetworkMetrics()
    }

    struct WorkItem: Sendable {
        let file: Int
        let chunk: Int
        var key: UInt64 { UInt64(file) << 32 | UInt64(chunk) }
    }

    /// Sums of chunk work may overlap because chunk tasks run concurrently.
    struct ChunkTiming: Sendable {
        var network = 0.0
        var decode = 0.0
        var decrypt = 0.0
        var decompress = 0.0
        var checksum = 0.0
        var write = 0.0
        var retries = 0
        var host = ""
        var fetchedBytes: UInt64 = 0
        var resumeCheck = 0.0
        var resumeChecksum = 0.0
        var resumeChecks = 0
        var resumeHits = 0
        var resumeCheckedBytes: UInt64 = 0
    }

    struct Prepared: Sendable {
        var paths: [[String]] = []       // per depot, per file: absolute path ("" = skipped)
        var existing: [[Bool]] = []      // per depot, per file: had content before this install
        var pending: [[WorkItem]] = []   // per depot: chunks still to fetch
        var journals: [URL] = []
        var totalBytes: UInt64 = 0
        var doneBytes: UInt64 = 0
        var totalUncompressed: UInt64 = 0
        var remainingUncompressed: UInt64 = 0
        var fileCount = 0
    }

    private nonisolated static func prepare(plans: [DepotPlan], installURL: URL, journalDir: URL) throws -> Prepared {
        let fm = FileManager.default
        var result = Prepared()
        var folded: [String: String] = [:]   // lowercased relative dir -> first spelling
        let journalNames = Set(plans.map { "depot_\($0.depotID)_\($0.manifestGID).journal" })
        // A journal for an older manifest describes different file contents.
        for name in (try? fm.contentsOfDirectory(atPath: journalDir.path)) ?? [] where !journalNames.contains(name) {
            try? fm.removeItem(at: journalDir.appendingPathComponent(name))
        }
        for plan in plans {
            try Task.checkCancellation()
            let journalURL = journalDir.appendingPathComponent("depot_\(plan.depotID)_\(plan.manifestGID).journal")
            let done = JournalWriter.load(journalURL)
            var paths: [String] = []
            var existing: [Bool] = []
            var pending: [WorkItem] = []
            paths.reserveCapacity(plan.manifest.files.count)
            for (fileIndex, file) in plan.manifest.files.enumerated() {
                // Symlinks (flag 0x200) have no Windows meaning here; skip them.
                guard file.flags & 0x200 == 0,
                      let relative = SteamInstallFiles.safeRelativePath(file.filename, folded: &folded) else {
                    if file.flags & 0x200 == 0 { SteamLog.trace("rejected manifest path in depot \(plan.depotID)") }
                    paths.append(""); existing.append(false); continue
                }
                let url = installURL.appendingPathComponent(relative)
                if file.isDirectory {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    paths.append(""); existing.append(false); continue
                }
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                var before = stat()
                let hadContent = stat(url.path, &before) == 0 && before.st_size > 0
                existing.append(hadContent)
                try sizeFile(url.path, to: file.size)
                paths.append(url.path)
                result.fileCount += 1
                result.totalUncompressed += file.size
                var pendingBytes: UInt64 = 0
                for (chunkIndex, chunk) in file.chunks.enumerated() {
                    let item = WorkItem(file: fileIndex, chunk: chunkIndex)
                    result.totalBytes += UInt64(chunk.compressedSize)
                    if done.contains(item.key) {
                        result.doneBytes += UInt64(chunk.compressedSize)
                    } else {
                        pending.append(item)
                        pendingBytes += UInt64(chunk.uncompressedSize)
                    }
                }
                // Space already allocated to an existing file is reused; only
                // its growth needs new space (sparse new files need all of it).
                let beforeSize = hadContent ? UInt64(before.st_size) : 0
                result.remainingUncompressed += hadContent
                    ? (file.size > beforeSize ? file.size - beforeSize : 0) : pendingBytes
            }
            result.paths.append(paths)
            result.existing.append(existing)
            result.pending.append(pending)
            result.journals.append(journalURL)
        }
        return result
    }

    /// Create or resize a file to its manifest length. Existing bytes below
    /// that length are kept so resumed and updated installs reuse them.
    private nonisolated static func sizeFile(_ path: String, to size: UInt64) throws {
        let fd = open(path, O_WRONLY | O_CREAT, 0o644)
        guard fd >= 0 else { throw SteamError.chunkDownloadFailed("Cannot create a game file (errno \(errno)).") }
        defer { close(fd) }
        var info = stat()
        if fstat(fd, &info) == 0, UInt64(info.st_size) == size { return }
        guard ftruncate(fd, off_t(size)) == 0 else {
            throw SteamError.chunkDownloadFailed("Cannot size a game file (errno \(errno)).")
        }
    }

    // MARK: - Chunks

    /// A chunk's ID is the SHA-1 of its uncompressed bytes. When a file
    /// already had content (an update, or a resume without a journal), bytes
    /// that already match are kept instead of downloaded again.
    private nonisolated static func chunkAlreadyPresent(_ chunk: DepotManifest.ChunkEntry, path: String,
                                                        timing: inout ChunkTiming) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        timing.resumeChecks += 1
        defer { timing.resumeCheck += max(0, ProcessInfo.processInfo.systemUptime - started) }
        let length = Int(chunk.uncompressedSize)
        guard chunk.sha.count == Int(CC_SHA1_DIGEST_LENGTH), length > 0,
              length <= ContentDecryptor.maximumChunkBytes else { return false }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: length)
        let read = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, length, off_t(chunk.offset)) }
        guard read == length else { return false }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let hashStarted = ProcessInfo.processInfo.systemUptime
        _ = CC_SHA1(buffer, CC_LONG(length), &digest)
        timing.resumeChecksum += max(0, ProcessInfo.processInfo.systemUptime - hashStarted)
        timing.resumeCheckedBytes += UInt64(length)
        let matches = Data(digest) == chunk.sha
        if matches { timing.resumeHits += 1 }
        return matches
    }

    private nonisolated static func fetchChunk(_ chunk: DepotManifest.ChunkEntry, plan: DepotPlan,
                                               path: String, attempts: Int, seed: Int) async throws -> ChunkTiming {
        var lastError: Error = SteamError.chunkDownloadFailed("No content server responded.")
        var result = ChunkTiming()
        var triedHosts = Set<String>()
        plan.networkMetrics.beginChunk()
        defer { plan.networkMetrics.endChunk() }
        for attempt in 0..<max(1, attempts) {
            try Task.checkCancellation()
            // Try a different host before revisiting one. Re-ranking after a
            // failure must not accidentally select that host again by index.
            guard let host = plan.health.choose(plan.hosts, seed: seed, avoiding: triedHosts) else { throw lastError }
            triedHosts.insert(host)
            let url = "\(host)/depot/\(plan.depotID)/chunk/\(chunk.shaHex)\(plan.auth[host] ?? "")"
            do {
                let encrypted: Data
                let requestStarted = ProcessInfo.processInfo.systemUptime
                do {
                    let start = ProcessInfo.processInfo.systemUptime
                    defer { result.network += ProcessInfo.processInfo.systemUptime - start }
                    encrypted = try await download(url, metrics: plan.networkMetrics)
                }
                let requestSeconds = ProcessInfo.processInfo.systemUptime - requestStarted
                result.fetchedBytes += UInt64(encrypted.count)
                let data: Data
                do {
                    let start = ProcessInfo.processInfo.systemUptime
                    var stages = ContentDecryptor.ProcessingTiming()
                    defer {
                        result.decode += ProcessInfo.processInfo.systemUptime - start
                        result.decrypt += stages.decrypt
                        result.decompress += stages.decompress
                        result.checksum += stages.checksum
                    }
                    data = try ContentDecryptor.processChunk(encryptedData: encrypted, depotKey: plan.key,
                                                             expectedCRC: chunk.crc,
                                                             expectedSize: Int(chunk.uncompressedSize), timing: &stages)
                }
                guard data.count == Int(chunk.uncompressedSize) else { throw SteamError.checksumMismatch }
                do {
                    let start = ProcessInfo.processInfo.systemUptime
                    defer { result.write += ProcessInfo.processInfo.systemUptime - start }
                    try write(data, to: path, offset: chunk.offset)
                }
                result.host = URL(string: host)?.host ?? "unknown"
                plan.health.recordSuccess(host, bytes: encrypted.count, seconds: requestSeconds)
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                result.retries += 1
                plan.health.recordFailure(host, reason: failureReason(error))
                SteamLog.trace("chunk attempt \(attempt + 1) failed: \(failureReason(error))")
                if attempt + 1 < attempts { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 400_000_000) }
            }
        }
        throw lastError
    }

    private nonisolated static func failureReason(_ error: Error) -> String {
        if let url = error as? URLError { return "url\(url.code.rawValue)" }
        if case SteamError.chunkDecodeFailed(let format) = error { return "decode-\(format)" }
        if case SteamError.checksumMismatch = error { return "checksum" }
        return "other"
    }

    private nonisolated static func write(_ data: Data, to path: String, offset: UInt64) throws {
        let fd = open(path, O_WRONLY)
        guard fd >= 0 else { throw SteamError.chunkDownloadFailed("Cannot open a game file (errno \(errno)).") }
        defer { close(fd) }
        try data.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let n = pwrite(fd, raw.baseAddress! + written, raw.count - written, off_t(offset) + off_t(written))
                guard n > 0 else { throw SteamError.chunkDownloadFailed("Cannot write a game file (errno \(errno)).") }
                written += n
            }
        }
    }

    private nonisolated static func download(_ urlString: String, metrics: ContentNetworkMetrics? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw SteamError.chunkDownloadFailed("Invalid content URL.") }
        metrics?.beginRequest()
        defer { metrics?.endRequest() }
        let (data, response) = try await http.data(from: url, delegate: metrics)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else {
            throw SteamError.chunkDownloadFailed("Content server returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return data
    }

    // MARK: - Manifest

    private func fetchManifest(depotID: UInt32, appID: UInt32, manifestGID: UInt64,
                               key: Data, hosts: [String], cacheCustomExecutables: Bool = true) async throws -> DepotManifest {
        let requestCode = try await manifestRequestCode(depotID: depotID, appID: appID, manifestGID: manifestGID)
        var lastError: Error = SteamError.manifestFetchFailed("No content server returned the manifest.")
        for host in hosts.prefix(6) {
            try Task.checkCancellation()
            let auth = await cdnAuthFragment(depotID: depotID, appID: appID, host: host)
            let code = requestCode == 0 ? "" : "/\(requestCode)"
            do {
                let raw = try await Self.download("\(host)/depot/\(depotID)/manifest/\(manifestGID)/5\(code)\(auth)")
                let cache = cacheCustomExecutables ? depotCache : nil
                return try await Task.detached(priority: .userInitiated) {
                    let (manifest, payload) = try Self.parseManifestKeepingPayload(raw, depotID: depotID, manifestGID: manifestGID, key: key)
                    // Valve's client reads a depot's manifest from steamapps/depotcache
                    // when it prepares a per-user custom executable. Keep it for such depots.
                    if let cache, manifest.files.contains(where: { $0.flags & DepotManifest.customExecutableFlag != 0 }) {
                        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                        let file = cache.appendingPathComponent("\(depotID)_\(manifestGID).manifest")
                        let existing = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                        if existing != payload.count { try? payload.write(to: file, options: .atomic) }
                    }
                    return manifest
                }.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                SteamLog.trace("manifest from a content server failed: \(error.localizedDescription)")
            }
        }
        throw lastError
    }

    private nonisolated static func parseManifest(_ raw: Data, depotID: UInt32, manifestGID: UInt64, key: Data) throws -> DepotManifest {
        try parseManifestKeepingPayload(raw, depotID: depotID, manifestGID: manifestGID, key: key).0
    }

    /// The manifest and the binary manifest bytes it was parsed from (unzipped, decrypted).
    private nonisolated static func parseManifestKeepingPayload(_ raw: Data, depotID: UInt32, manifestGID: UInt64,
                                                                key: Data) throws -> (DepotManifest, Data) {
        // Content servers deliver the manifest as a single-entry ZIP.
        let payload = raw.starts(with: [0x50, 0x4B]) ? try unzipSingleFile(raw) : raw
        if let plain = try? DepotManifest.parse(depotID: depotID, manifestGID: manifestGID, data: payload, depotKey: key),
           !plain.files.isEmpty {
            return (plain, payload)
        }
        // Older depots encrypt the whole manifest with the depot key.
        let decrypted = try ContentDecryptor.decryptChunk(encryptedData: payload, depotKey: key)
        let inflated = (try? ContentDecryptor.decompressChunk(compressedData: decrypted, expectedSize: 0)) ?? decrypted
        return (try DepotManifest.parse(depotID: depotID, manifestGID: manifestGID, data: inflated, depotKey: key), inflated)
    }

    /// steamapps/depotcache while an install runs.
    private var depotCache: URL?

    /// Extract the single deflated entry from a manifest ZIP. No zip lib needed —
    /// parse the local file header and inflate the raw deflate stream.
    nonisolated static func unzipSingleFile(_ data: Data) throws -> Data {
        let data = Data(data)  // zero-based indices
        guard data.count > 30,
              data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 else {
            throw SteamError.manifestFetchFailed("Not a zip")
        }
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o+1]) << 8 | Int(data[o+2]) << 16 | Int(data[o+3]) << 24 }
        let method = u16(8)
        let compSize = u32(18)
        let uncompSize = u32(22)
        let nameLen = u16(26), extraLen = u16(28)
        let start = 30 + nameLen + extraLen
        guard start + compSize <= data.count, method == 0 || method == 8,
              uncompSize <= ContentDecryptor.maximumChunkBytes * 4 else {
            throw SteamError.manifestFetchFailed("Bad zip entry (method \(method))")
        }
        let entry = data.subdata(in: start..<(start + compSize))
        if method == 0 { return entry }

        // Zip stores raw deflate — inflate with zlib, negative windowBits
        var strm = z_stream()
        let cap = max(uncompSize, 1024)
        var out = Data(count: cap)
        var n = -1
        entry.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                strm.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: UInt8.self).baseAddress)
                strm.avail_in = UInt32(entry.count)
                strm.next_out = dst.bindMemory(to: UInt8.self).baseAddress
                strm.avail_out = UInt32(cap)
                guard inflateInit2_(&strm, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return }
                let r = inflate(&strm, Z_FINISH)
                inflateEnd(&strm)
                if r == Z_STREAM_END { n = Int(strm.total_out) }
            }
        }
        guard n >= 0 else { throw SteamError.decompressionFailed }
        out.count = n
        return out
    }

    // MARK: - Depot Key

    private func depotKey(depotID: UInt32, appID: UInt32) async throws -> Data {
        if let cached = depotKeys[depotID] { return cached }
        try await session.ensureConnected()

        var request = CMsgClientGetDepotDecryptionKey()
        request.depotID = depotID
        request.appID = appID

        let response = try await session.sendAndWait(
            eMsg: .clientGetDepotDecryptionKey,
            body: request.serialize(),
            responseEMsg: .clientGetDepotDecryptionKeyResponse,
            timeout: 15
        )

        let keyResponse = try CMsgClientGetDepotDecryptionKeyResponse.deserialize(from: response.body)
        // Steam only issues keys for depots this account owns.
        guard EResult(rawValue: UInt32(keyResponse.eresult))?.isSuccess == true,
              keyResponse.depotEncryptionKey.count == 32 else {
            SteamLog.event("[steam-depot] depot-key refused app=\(appID) depot=\(depotID) eresult=\(keyResponse.eresult)")
            throw SteamError.depotKeyNotFound(depotID)
        }

        depotKeys[depotID] = keyResponse.depotEncryptionKey
        return keyResponse.depotEncryptionKey
    }

    // MARK: - Manifest Request Code

    private func manifestRequestCode(depotID: UInt32, appID: UInt32, manifestGID: UInt64) async throws -> UInt64 {
        try await session.ensureConnected()
        var encoder = ProtobufEncoder()
        encoder.writeUInt32(fieldNumber: 1, value: appID)
        encoder.writeUInt32(fieldNumber: 2, value: depotID)
        encoder.writeUInt64(fieldNumber: 3, value: manifestGID)

        let responseData = try await session.callServiceMethod(
            method: .getManifestRequestCode,
            body: encoder.data,
            timeout: 15
        )

        var decoder = ProtobufDecoder(responseData)
        while let tag = try decoder.readTag() {
            if tag.fieldNumber == 1 {
                // manifest_request_code is fixed64 on the wire
                return tag.wireType == .fixed64 ? try decoder.readFixed64() : try decoder.readVarint()
            }
            try decoder.skip(wireType: tag.wireType)
        }

        return 0 // No request code needed (older depots)
    }

    // MARK: - CDN Discovery + Auth

    /// Content server discovery via the public Web API
    /// (IContentServerDirectoryService/GetServersForSteamPipe). No account
    /// token is attached; the directory does not require one.
    enum ServerEligibility: Equatable { case usable, noHTTPS, other }

    /// Directory fields as served by GetServersForSteamPipe: https_support
    /// ("mandatory", "optional", "unavailable"), use_as_proxy, and an optional
    /// allowed_app_ids restriction.
    nonisolated static func serverEligibility(_ server: [String: Any], appID: UInt32) -> ServerEligibility {
        if let https = (server["https_support"] as? String)?.lowercased(), https != "mandatory", https != "optional" {
            return .noHTTPS
        }
        if (server["use_as_proxy"] as? Bool) == true || (server["use_as_proxy"] as? NSNumber)?.boolValue == true {
            return .other
        }
        if let allowed = server["allowed_app_ids"] as? [Any], !allowed.isEmpty,
           !allowed.contains(where: { ($0 as? NSNumber)?.uint32Value == appID || ($0 as? String) == String(appID) }) {
            return .other
        }
        return .usable
    }

    private func contentServers(appID: UInt32) async throws -> [String] {
        var hosts: [String] = []
        do {
            guard let url = URL(string: "https://api.steampowered.com/IContentServerDirectoryService/GetServersForSteamPipe/v1/?cell_id=\(session.cellID)&max_servers=20") else {
                throw SteamError.chunkDownloadFailed("Bad content directory URL")
            }
            let (data, response) = try await Self.http.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SteamError.chunkDownloadFailed("Content directory HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resp = json["response"] as? [String: Any],
                  let servers = resp["servers"] as? [[String: Any]] else {
                throw SteamError.chunkDownloadFailed("Content directory returned unexpected data")
            }
            // In the directory's order. The directory marks some CDN servers
            // https_support "unavailable"; requesting them over HTTPS fails the
            // TLS handshake (NSURLError -1200). Such servers, proxy-only entries
            // and servers restricted to other apps are skipped.
            var skippedHTTP = 0, skippedOther = 0
            for server in servers {
                let host = (server["vhost"] as? String) ?? (server["host"] as? String) ?? ""
                guard Self.usableContentHost(host) else { skippedOther += 1; continue }
                switch Self.serverEligibility(server, appID: appID) {
                case .usable: break
                case .noHTTPS: skippedHTTP += 1; continue
                case .other: skippedOther += 1; continue
                }
                let entry = "https://\(host)"
                if !hosts.contains(entry) { hosts.append(entry) }
            }
            SteamLog.event("[steam-cdn] offered=\(servers.count) usable=\(hosts.count) skipped-no-https=\(skippedHTTP) skipped-other=\(skippedOther)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            SteamLog.trace("content directory failed: \(error.localizedDescription)")
        }
        let fallback = "https://steampipe.akamaized.net"
        if !hosts.contains(fallback) { hosts.append(fallback) }
        return hosts
    }

    nonisolated static func usableContentHost(_ host: String) -> Bool {
        guard host.contains("."), !host.contains(" "), !host.contains("/"), !host.contains("*"),
              !host.contains("lancache"), !host.contains(":") else { return false }
        return host.hasSuffix(".steamcontent.com") || host.hasSuffix(".akamaized.net") ||
            host.hasSuffix(".steampipe.steamcontent.com") || host.hasSuffix(".steamstatic.com")
    }

    /// Unified-service GetCDNAuthToken → "?auth=…" query fragment for this
    /// depot on this host. An empty token is normal outside regional edge
    /// networks. Cached per depot and host.
    private func cdnAuthFragment(depotID: UInt32, appID: UInt32, host: String) async -> String {
        let cacheKey = "\(depotID)|\(host)"
        if let cached = cdnAuthTokens[cacheKey] { return cached }

        // host_name must be the bare hostname, not the https:// URL
        let bareHost = URL(string: host)?.host ?? host

        var encoder = ProtobufEncoder()
        encoder.writeUInt32(fieldNumber: 1, value: depotID)  // depot_id = 1
        encoder.writeString(fieldNumber: 2, value: bareHost) // host_name = 2
        encoder.writeUInt32(fieldNumber: 3, value: appID)    // app_id = 3

        do {
            try await session.ensureConnected()
            let responseData = try await session.callServiceMethod(
                method: .getCDNAuthToken,
                body: encoder.data,
                timeout: 10
            )
            var decoder = ProtobufDecoder(responseData)
            var token = ""
            while let tag = try decoder.readTag() {
                if tag.fieldNumber == 1 { token = try decoder.readString() } else { try decoder.skip(wireType: tag.wireType) }
            }
            let fragment = token.isEmpty ? "" : (token.hasPrefix("?") || token.hasPrefix("&") ? token : "?auth=\(token)")
            cdnAuthTokens[cacheKey] = fragment
            return fragment
        } catch {
            SteamLog.trace("content authorization request failed; continuing without a token")
            cdnAuthTokens[cacheKey] = ""
            return ""
        }
    }
}

struct ContentControlRequest: Sendable {
    let url: URL
    let bytes: UInt64
}

struct ContentControlTrial: Codable, Sendable {
    let bytes: UInt64
    let seconds: Double
}

/// Direct URLSession control: bounded encrypted response downloads to temporary
/// files, without Steam decode/assembly. Reuses connections on one CDN host.
/// The caller supplies requests from a key-authorized, decrypted manifest.
enum ContentControl {
    static func run(_ requests: [ContentControlRequest]) async throws -> [ContentControlTrial] {
        guard !requests.isEmpty, requests.count <= 256,
              let host = requests.first?.url.host,
              requests.allSatisfy({ $0.url.host == host && $0.bytes > 0 && $0.bytes <= 8 * 1024 * 1024 }),
              requests.reduce(UInt64(0), { $0 + $1.bytes }) <= 64 * 1024 * 1024 else {
            throw SteamError.chunkDownloadFailed("Invalid control sample.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let http = URLSession(configuration: config)
        defer { http.invalidateAndCancel() }
        var results: [ContentControlTrial] = []
        for _ in 0..<3 {
            try Task.checkCancellation()
            let started = ProcessInfo.processInfo.systemUptime
            let bytes = try await withThrowingTaskGroup(of: UInt64.self) { group in
                var next = 0
                func enqueue() {
                    let request = requests[next]
                    next += 1
                    group.addTask {
                        try Task.checkCancellation()
                        let (file, response) = try await http.download(from: request.url)
                        defer { try? FileManager.default.removeItem(at: file) }
                        try Task.checkCancellation()
                        guard let response = response as? HTTPURLResponse,
                              response.statusCode == 200, response.url?.host == host,
                              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                              UInt64(size) == request.bytes else {
                            throw SteamError.chunkDownloadFailed("Control response did not match its authorized sample.")
                        }
                        return UInt64(size)
                    }
                }
                for _ in 0..<min(8, requests.count) { enqueue() }
                var total: UInt64 = 0
                while let count = try await group.next() {
                    total += count
                    if next < requests.count { enqueue() }
                }
                return total
            }
            let wall = max(0.000001, ProcessInfo.processInfo.systemUptime - started)
            results.append(ContentControlTrial(bytes: bytes, seconds: wall))
        }
        return results
    }
}

/// CPU time of the entire Mach process, not attribution to one download task.
/// One core fully occupied for one wall second reports one average core;
/// concurrent cores can legitimately make this larger than one.
struct ContentProcessCPUInterval {
    private let began = Self.readSeconds()

    private static func readSeconds() -> Double? {
        var usage = rusage()
        #if os(Linux)
        let who = Int32(RUSAGE_SELF.rawValue)
        #else
        let who = RUSAGE_SELF
        #endif
        guard getrusage(who, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1000000 +
               Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1000000
    }

    func report(wall: Double) -> String {
        guard wall.isFinite, wall > 0, let began, let ended = Self.readSeconds(),
              ended >= began, (ended - began).isFinite, ((ended - began) / wall).isFinite else {
            return "process-cpu=unavailable"
        }
        return String(format: "process-cpu-seconds=%.6fs process-cpu-cores=%.3f", ended - began, (ended - began) / wall)
    }
}

/// Completion-driven tuning, owned by the task-group consumer. Uses useful
/// compressed bytes per wall second, excluding resumed chunks and retry bytes.
/// Processing durations are load proxies, not a measurement of CPU utilization.
struct ContentConcurrency {
    private(set) var limit = 8
    private(set) var peak = 8
    private var started: Double
    private var chunks = 0
    private var bytes = 0.0
    private var network = 0.0
    private var processing = 0.0
    private var retries = 0
    private var probe: (limit: Int, rate: Double)?
    private var cooldown = 0

    init(started: Double) { self.started = started }

    mutating func observe(now: Double, bytes usefulBytes: UInt64, network networkTime: Double,
                          processing processingTime: Double, retries retryCount: Int) -> String? {
        guard now.isFinite, now >= started, networkTime.isFinite, networkTime >= 0,
              processingTime.isFinite, processingTime >= 0, retryCount >= 0,
              usefulBytes > 0 else { return nil }
        chunks += 1
        bytes += Double(usefulBytes)
        network += networkTime
        processing += processingTime
        retries += retryCount
        let elapsed = now - started
        // Observe a full batch and at least two seconds before judging it.
        guard chunks >= limit, elapsed >= 2 else { return nil }
        let rate = bytes / elapsed
        let retryPressure = retries >= max(2, chunks / 4)
        let processingPressure = processing > network && processing > 0
        started = now
        chunks = 0; bytes = 0; network = 0; processing = 0; retries = 0
        if retryPressure || processingPressure {
            probe = nil
            cooldown = 2
            let reduced = retryPressure ? max(2, limit / 2) : max(2, limit - 2)
            guard reduced != limit else { return nil }
            limit = reduced
            return retryPressure ? "retries" : "processing"
        }
        if let previous = probe {
            probe = nil
            // Keep a larger batch only when it improved useful throughput.
            if rate < previous.rate * 1.05 {
                limit = previous.limit
                cooldown = 2
                return "probe-no-gain"
            }
            return "probe-gain"
        }
        if cooldown > 0 { cooldown -= 1; return nil }
        guard limit < 16 else { return nil }
        probe = (limit, rate)
        limit = min(16, limit + 2)
        peak = max(peak, limit)
        return "probe"
    }
}

/// Chunk-request measurements shared by one depot. Delegate callbacks and
/// download tasks may run concurrently; all mutable state is protected by lock.
/// Keep only hostnames and numeric fields, never URLs or authorization headers.
final class ContentNetworkMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private struct Samples {
        var count = 0
        var seconds = 0.0
        mutating func add(_ start: Date?, _ end: Date?) {
            guard let start, let end else { return }
            let elapsed = end.timeIntervalSince(start)
            guard elapsed.isFinite, elapsed >= 0 else { return }
            count += 1
            seconds += elapsed
        }
        var description: String {
            count == 0 ? "unavailable" : String(format: "%.3fs/%d", seconds, count)
        }
    }
    private struct Host {
        var transactions = 0, reused = 0
        var responseBytes: Int64 = 0
        var dns = Samples(), connect = Samples(), tls = Samples(), ttfb = Samples()
        var protocols: [String: Int] = [:]
        var statuses: [Int: Int] = [:]
    }
    private let lock = NSLock()
    private var hosts: [String: Host] = [:]
    private var requests = 0, completed = 0, callbacks = 0
    private var activeRequests = 0, peakRequests = 0
    private var activeChunks = 0, peakChunks = 0

    func beginChunk() {
        lock.lock(); defer { lock.unlock() }
        activeChunks += 1; peakChunks = max(peakChunks, activeChunks)
    }
    func endChunk() {
        lock.lock(); defer { lock.unlock() }; activeChunks -= 1
    }
    func beginRequest() {
        lock.lock(); defer { lock.unlock() }
        requests += 1; activeRequests += 1; peakRequests = max(peakRequests, activeRequests)
    }
    func endRequest() {
        lock.lock(); defer { lock.unlock() }; completed += 1; activeRequests -= 1
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); defer { lock.unlock() }
        callbacks += 1
        for metric in metrics.transactionMetrics {
            let hostname = metric.request.url?.host ?? "unknown"
            var host = hosts[hostname] ?? Host()
            host.transactions += 1
            if metric.isReusedConnection { host.reused += 1 }
            host.responseBytes += max(0, metric.countOfResponseBodyBytesReceived)
            host.dns.add(metric.domainLookupStartDate, metric.domainLookupEndDate)
            host.connect.add(metric.connectStartDate, metric.connectEndDate)
            host.tls.add(metric.secureConnectionStartDate, metric.secureConnectionEndDate)
            host.ttfb.add(metric.fetchStartDate, metric.responseStartDate)
            let value = metric.networkProtocolName ?? "unknown"
            let protocolName = ["http/1.0", "http/1.1", "h2", "h3"].contains(value) ? value : "other"
            host.protocols[protocolName, default: 0] += 1
            host.statuses[(metric.response as? HTTPURLResponse)?.statusCode ?? 0, default: 0] += 1
            hosts[hostname] = host
        }
    }

    func report(depotID: UInt32) -> [String] {
        lock.lock(); defer { lock.unlock() }
        var lines = ["[steam-depot] network depot=\(depotID) requests=\(requests) completed=\(completed) metrics-callbacks=\(callbacks) active-requests=\(activeRequests) peak-active-requests=\(peakRequests) active-chunks=\(activeChunks) peak-active-chunks=\(peakChunks)"]
        for name in hosts.keys.sorted() {
            let host = hosts[name]!
            let protocols = host.protocols.keys.sorted().map { "\($0):\(host.protocols[$0]!)" }.joined(separator: ",")
            let statuses = host.statuses.keys.sorted().map { "\($0):\(host.statuses[$0]!)" }.joined(separator: ",")
            lines.append("[steam-cdn] timing depot=\(depotID) host=\(name) transactions=\(host.transactions) reused=\(host.reused) dns=\(host.dns.description) connect=\(host.connect.description) tls=\(host.tls.description) ttfb=\(host.ttfb.description) response-bytes=\(host.responseBytes) protocols=\(protocols) statuses=\(statuses)")
        }
        return lines
    }
}

/// Per-install content-server health and observed valid-payload HTTP rates.
/// Failure counts take precedence. Healthy unsampled hosts get initial trials;
/// one in eight selections explores a healthy peer to refresh its rate.
final class ContentHostHealth: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String: Int] = [:]
    private var rates: [String: Double] = [:]
    private var selections = 0
    private var reported = 0

    func order(_ hosts: [String], seed: Int) -> [String] {
        guard !hosts.isEmpty else { return hosts }
        let offset = ((seed % hosts.count) + hosts.count) % hosts.count
        let rotated = (0..<hosts.count).map { hosts[($0 + offset) % hosts.count] }
        lock.lock()
        let counts = failures, observed = rates
        selections &+= 1
        let selection = selections
        lock.unlock()
        var ordered = rotated.enumerated().sorted {
            let a = counts[$0.element] ?? 0, b = counts[$1.element] ?? 0
            if a != b { return a < b }
            let ar = observed[$0.element], br = observed[$1.element]
            // Obtain a rate before judging a healthy server's performance.
            if (ar == nil) != (br == nil) { return ar == nil }
            if let ar, let br, ar != br { return ar > br }
            return $0.offset < $1.offset
        }.map(\.element)
        if selection > 0 && selection % 8 == 0 {
            let lowest = counts[ordered[0]] ?? 0
            let peers = rotated.filter { (counts[$0] ?? 0) == lowest }
            let probe = peers[(selection / 8 - 1) % peers.count]
            ordered.removeAll { $0 == probe }
            ordered.insert(probe, at: 0)
        }
        return ordered
    }

    func choose(_ hosts: [String], seed: Int, avoiding tried: Set<String>) -> String? {
        let ordered = order(hosts, seed: seed)
        return ordered.first { !tried.contains($0) } ?? ordered.first
    }

    func recordFailure(_ host: String, reason: String) {
        lock.lock()
        failures[host, default: 0] += 1
        let report = failures[host] == 3 && reported < 8
        if report { reported += 1 }
        lock.unlock()
        if report {
            let server = host.replacingOccurrences(of: "https://", with: "")
            DispatchQueue.main.async { SteamLog.event("[steam-cdn] host demoted host=\(server) reason=\(reason)") }
        }
    }

    func recordSuccess(_ host: String, bytes: Int = 0, seconds: Double = 0) {
        lock.lock()
        if let count = failures[host], count > 0 { failures[host] = count - 1 }
        if bytes > 0, seconds.isFinite, seconds > 0 {
            let rate = Double(bytes) / seconds
            if rate.isFinite {
                rates[host] = rates[host].map { $0 * 0.75 + rate * 0.25 } ?? rate
            }
        }
        lock.unlock()
    }
}

/// Append-only record of completed chunks for one depot manifest. Lines are
/// hexadecimal work-item keys. A lost tail only causes those chunks to be
/// fetched again.
final class JournalWriter {
    private let handle: FileHandle
    private var buffer = ""
    private var pending = 0

    init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forUpdating: url)
        // A previous attempt killed mid-write can leave a partial last line;
        // start on a fresh line so the first new key is not glued onto it.
        let end = handle.seekToEndOfFile()
        if end > 0 {
            handle.seek(toFileOffset: end - 1)
            if handle.readData(ofLength: 1) != Data([0x0A]) { buffer = "\n" }
            handle.seekToEndOfFile()
        }
    }

    func append(_ key: UInt64) {
        buffer += String(key, radix: 16) + "\n"
        pending += 1
        if pending >= 64 { flush() }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        handle.write(Data(buffer.utf8))
        buffer = ""; pending = 0
    }

    func close() {
        flush()
        try? handle.close()
    }

    static func load(_ url: URL) -> Set<UInt64> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var keys = Set<UInt64>()
        for line in text.split(separator: "\n") { if let key = UInt64(line, radix: 16) { keys.insert(key) } }
        return keys
    }
}
