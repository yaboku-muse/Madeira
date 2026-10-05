// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation
import zlib
#if canImport(CryptoKit)
import CryptoKit
#endif

// Valve's client components for Madeira Dock, fetched from Valve's own update
// CDN (one host, HTTPS) and checked against pinned sizes and SHA-256 sums; the
// unpacked steamclient64.dll must be the client build the Dock host supports.
// Pins never follow a moving client manifest. No Valve binary is bundled.
enum SteamRuntimeFiles {
    struct Package: Sendable {
        let file: String
        let bytes: Int
        let sha256: String
    }
    static let origin = "https://client-update.akamai.steamstatic.com/"
    static let packages = [
        Package(file: "bins_win64.zip.36f5d9202e79ab2aa3e3c5902e84bbd799d31fc0", bytes: 63_700_191,
                sha256: "93f5b6bea0267fd85dc8cc823fdab5c5fb55d7f3a1deab0598acefef0e133bce"),
        Package(file: "bins_codecs_win64.zip.9edc714e8a6f8c2881ac0cfdc2af382070e42c2e", bytes: 12_705_333,
                sha256: "5a32e6966666f6246acd2c92b98f1eee52e717d9085fe901c8825df77da48ffb"),
        Package(file: "steam_win64_steamrow.zip.6f024698857e81681cf673422a8c1a4d06e2be7f", bytes: 2_668_385,
                sha256: "5dbc39918056cc8b7815daaa181eb3fa19a264b25dab33f3d1ad631b79ee3bb8")
    ]
    static let clientSHA256 = "caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee"
    static let relativeRoot = "Program Files (x86)/Steam"
    static let windowsRoot = "C:\\Program Files (x86)\\Steam"

    // SHA-256 of overlapping files from the three previously pinned January
    // Valve packages. Metadata only; unknown existing bytes are never replaced.
    static let legacyFileSHA256: [String: String] = [
        "bin/audio.dll": "3a9cb2108001d5bde5bdeb49c36436ce484e3ccec370330fd06e34933ec877b7",
        "bin/audio64.dll": "7766b0afb01b1fc6a223d795d08be2f6f965f41d9a18e25829975f3eff812a34",
        "bin/chromehtml.dll": "8fe79a1fdbe89d489bbdae059c8c34dffb20de7f9a5298b56d6fff92d3e9e9c2",
        "bin/drivers.exe": "9daf97b4123452c29e1b9b1cb9b9e56e68441e4e2cb979b926c2c120e64ed404",
        "bin/filesystem_stdio.dll": "0a2a961facbd2aab13cb1a1e9779ac148dacde0b4fa89e4f0518c51ed6e64e89",
        "bin/fossilize-replay.exe": "4b5e5b37d610ab4d62247c843848e53b72c030a8a15884547830c94724ce9d1e",
        "bin/fossilize-replay64.exe": "a1eeef908e9487eb06c9d702710a51175bccb1cee2aa2c5799ec021a8e8907f4",
        "bin/friendsui.dll": "e6c80a74a30ef04c8f8142a7b0a379048f14dfd8a483fd89d326c5a79851884e",
        "bin/gameoverlayui.dll": "d3dc4076bee30b4cf3b53cb08be16e898c267181c1a078aa73fdcaa5b61f72dd",
        "bin/nattypeprobe.dll": "34ab8bba51b73e4427fe57d5f9515b32fcb9113d1ba3cc4b7835b0a19f1f57b8",
        "bin/secure_desktop_capture.exe": "de6d17b1b559a4ce9566f231f041e96ea19f0c14a24b9fd13b66025b78956cac",
        "bin/service_current_versions.vdf": "61d84529c270118044e089dde75c906db56a135a64575f6d6774de396760a15f",
        "bin/service_minimum_versions.vdf": "a75ecb06d45017d2289ec27dac9f418c6ef82a9352e012670a0c67161c25c52c",
        "bin/shaders/d3d10overlay.fxo": "60dd387077d690edd80cfab427823861ceb8190a5e98e49e8918f2ecba4468b7",
        "bin/shaders/d3d9overlay.cso": "6bba8ae279e09b6d1bf0ca6dd555327188e02253c30ae963904c1c7ce3df98ce",
        "bin/steam_monitor.exe": "a4a7f8ad85943cbee315df93560f76984c0fe0963fc57aed6b9061b962f477b0",
        "bin/steamservice.dll": "0feb20a1877c221d157c0cb426ad55d251bd9e7e6e28aebd4a5ae8fc1708d635",
        "bin/steamservice.exe": "72a406a6a2d3e282ab4b468ed8bfadf171fdd03a97969d6214a5da6fdb8dbd03",
        "bin/steamxboxutil.exe": "abc77e35915f34a81086f42b09c3cdaf95a5f77154f5d5488ab287e8d0869cc2",
        "bin/steamxboxutil64.exe": "a087d44de6bdf61e7112bc3ece6ac89a515b080b9cc45c4a7330dd518082f77a",
        "bin/vgui2_s.dll": "41c26ef770cddb01ac8b96d01d1f116819a995aecf5ec1d82897e67ce56f76e7",
        "bin/vulkandriverquery.exe": "07676edd2bfd4db789b90cc4423d8a058db0875165838d5c5d6f02f129b7e232",
        "bin/vulkandriverquery64.exe": "dbccaaa296cb7cfcb0e070848668504cc398de1a740c0650d5c06b983a4d7bd6",
        "bin/x64launcher.exe": "131af4d579e85754a9370e20112b46a4eff115ab92915735a9b001383c7ea094",
        "bin/x86launcher.exe": "f8f9aa826d8885e91f3a1ce99e304963a159b413172bc8e7fc14a7990bff4ec3",
        "crashhandler.dll": "e90218de2e066babb8220e61c787eb75a7c037ab65e7d44d0241264e2952879a",
        "crashhandler64.dll": "209d560ac43ce5dcf984c63d4ea41b64a0f6f4e42c53436a56be72c1f4e4cedf",
        "gameoverlayrenderer.dll": "23bea6b8a97460ffe997892bc9e59085c977a4b62414356c1cccac13912251ee",
        "gameoverlayrenderer64.dll": "b70610b16a2ed5016d0063e2d97cfe7b95c064ab16cf15c1f9a4920d667db3da",
        "gameoverlayui64.exe": "bb11a9a91a859c69a4cc62c916c383d6631709aaedc38aa110296a783861c517",
        "sdl3.dll": "db01ec466db9c4e19cc5fe8c878ac89bc1b6057136432554842b3cd4dca88669",
        "steam.dll": "d9a06d104da9b119207125b61f590eee1618b1d1f84c7322e6202f0fe87b692a",
        "steam.exe": "1d2fbcc0402dc5a1f64b2e1d924e6e38e1dd76197c0246ddf89094fb86fda915",
        "steam.signatures": "6a95380a29fe76f8745b8c33ad0568604321c13750d7a6a259d199397d182b5b",
        "steamclient.dll": "dd5cd49c4c7fa7187ae0c0d28cf0b1de234665d35ce1673d2b24b77c71250dab",
        "steamclient64.dll": "71b391fe9f3e2006cbc81a5c75eef3eb4186012deabfdb2c8b7e8d4850ecf640",
        "steamerrorreporter.exe": "55090921c58be9dd0237e04262009022fbd4758173253675695ac06609dcd68b",
        "steamerrorreporter64.exe": "5c91c718c2f09f396b59bf1aea026e6b770df16e1c2e864c0f288357e3c373b1",
        "steamoverlayvulkanlayer.dll": "29e99db274c1ffe57c162ba7d1644a4518fdf32becb57c4bf6f393dfd1f4c979",
        "steamoverlayvulkanlayer64.dll": "975ce52fa9e9e598019c5fbf40400da4c1690fec37b59d372a4fa31e4f555f8c",
        "steamsysinfo.exe": "2358ad47cb1996bedb53732e00dad7a0895f79366031b73f065a8cc6605b103f",
        "steamui.dll": "0cad7c69ace13e802be17beb06df299f7f733f01b4450a74bc68709494b21ddb",
        "streaming_client.exe": "5b8cd9da4a4653fdd86f98eb08e219f5a8b5f641c89ef679bdeb9fe6cb5daafc",
        "tier0_s.dll": "a55dd102547933009247095a8bab8885f8e76aef12b423721490b4d259ab6a17",
        "tier0_s64.dll": "af89cb6e94b20a5660d8f33427460fcd3b5e43e16b13372321d09cebab1288b8",
        "video.dll": "70d3e8337b6a10d3341e2377b46e552e5bdccb4c9a24030f3c13094f54170900",
        "video64.dll": "056f3c608535bac07eacd790e0096fb11b5644b1f79a05f1a42ba40b452e367e",
        "vklayer_steam_fossilize.dll": "0ba2b0f427e7adaed61f3a41318ce6e9b4538bc26050b0fea492adf1af2b4b97",
        "vklayer_steam_fossilize64.dll": "a0ba8bdcfeb9cdb6499abae17f85b48dea98386b714b9b63053af3bf15035bfd",
        "vstdlib_s.dll": "321d0c5dfd92baf5981dff354f49d582c6da412a41d4b1cccc0aa7b9e34c8f26",
        "vstdlib_s64.dll": "9bb287b195f0a246f68ea462371178d9a2ebc23b03df295606ef189910aee2d2",
    ]

    static let criticalFileSHA256: [String: String] = [
        "SDL3.dll": "e453238bb31d593a87e7de87f1f5985fa11d2f9ed12a83fc65c9a52857a30118",
        "libavcodec-62.dll": "59cd1cab28cc8cbffd0b6cf0afc7c2b00ee650c3d25eaa2847347c7fe3188305",
        "libavfilter-11.dll": "2d97b666632dde8c8f29ce55999e77318c5852cfb88564f6c39ee5d3c651a790",
        "libavformat-62.dll": "3f2bfa0c595523aca218d00302a7ba6be2b2123ad3f777c5bb04dd2d9497426a",
        "libavutil-60.dll": "93c6c86eb17cf92d0c18a93f55fef2904142f9bcfbd97278052e6ebc0a71fa4b",
        "libswresample-6.dll": "d9f663184904ad342c2f4a28b8f5d431856f24b32a5c83b231759c75ed38dcd6",
        "libswscale-9.dll": "e54dbe70f94dd1a4b66c75270a6641c03b2174be0ecd345843316ab080dad70a",
        "steam.exe": "48ea0576865d2dfda26001b7b210c3f7559d46e647424cd11704eb1ea842fe5a",
        "steamclient64.dll": "caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee",
        "video64.dll": "d5b40072bf91ffb22cc6ebbf59b7b13241d4a02845329f0a4d44453381106fe5",
    ]

    enum Publication: Equatable { case keep, create, replace }
    static func publication(existingSHA256: String?, desiredSHA256: String, legacySHA256: String?) throws -> Publication {
        guard let existingSHA256 else { return .create }
        if existingSHA256 == desiredSHA256 { return .keep }
        if let legacySHA256, existingSHA256 == legacySHA256 { return .replace }
        throw Failure.conflict
    }

    /// Preflight the whole file set, then preserve verified old bytes before
    /// atomic replacement. Interrupted publication can resume from old/new files.
    static func publish(stage: URL, drive: URL, backupRoot: URL, names: [String],
                        legacy: [String: String] = legacyFileSHA256,
                        hash: (Data) -> String, checkQuiescent: () throws -> Void,
                        beforeCommit: () throws -> Void) throws {
        let fm = FileManager.default
        var seen = Set<String>()
        var plan: [(name: String, source: URL, target: URL, prior: String?, mode: Publication)] = []
        for name in names.sorted(by: { $0 == "steam.exe" ? false : ($1 == "steam.exe" ? true : $0 < $1) }) {
            guard validPath(name), seen.insert(name.lowercased()).inserted else { throw Failure.invalidPackage }
            let source = try destination(name, under: stage)
            let target = try destination(relativeRoot + "/" + name, under: drive)
            let desired = hash(try Data(contentsOf: source, options: .mappedIfSafe))
            let prior = fm.fileExists(atPath: target.path) ? hash(try Data(contentsOf: target, options: .mappedIfSafe)) : nil
            let mode = try publication(existingSHA256: prior, desiredSHA256: desired, legacySHA256: legacy[name.lowercased()])
            plan.append((name, source, target, prior, mode))
        }
        try checkQuiescent()
        for item in plan where item.mode == .replace {
            let backup = try destination(item.name, under: backupRoot)
            if fm.fileExists(atPath: backup.path) {
                guard hash(try Data(contentsOf: backup, options: .mappedIfSafe)) == item.prior else { throw Failure.conflict }
            } else {
                try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item.target, to: backup)
                guard hash(try Data(contentsOf: backup, options: .mappedIfSafe)) == item.prior else { throw Failure.conflict }
            }
        }
        try checkQuiescent()
        try beforeCommit()
        for item in plan where item.mode != .keep {
            try checkQuiescent()
            _ = try destination(relativeRoot + "/" + item.name, under: drive)
            let current = fm.fileExists(atPath: item.target.path) ? hash(try Data(contentsOf: item.target, options: .mappedIfSafe)) : nil
            guard current == item.prior else { throw Failure.conflict }
            try fm.createDirectory(at: item.target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: item.source, options: .mappedIfSafe).write(to: item.target, options: .atomic)
        }
    }

    /// Dock hosts Valve's AMD64 client. Reject a mixed root runtime before
    /// publishing it; the x86 steamclient for 32-bit games remains valid.
    static func isAMD64Image(_ data: Data) -> Bool {
        guard data.count >= 64 else { return false }
        func byte(_ offset: Int) -> Int { Int(data[data.startIndex + offset]) }
        func word(_ offset: Int) -> Int { byte(offset) | byte(offset + 1) << 8 }
        guard word(0) == 0x5a4d else { return false }
        let pe = byte(60) | byte(61) << 8 | byte(62) << 16 | byte(63) << 24
        guard pe >= 64, pe <= data.count - 26 else { return false }
        return word(pe) == 0x4550 && word(pe + 2) == 0 && word(pe + 4) == 0x8664 && word(pe + 24) == 0x20b
    }

    enum Failure: LocalizedError {
        case invalidPackage, conflict, activeSession, prefixMissing
        var errorDescription: String? {
            switch self {
            case .invalidPackage: return "Steam's components could not be verified. Try downloading them again."
            case .conflict: return "Existing Steam files need attention. They were kept. Use the desktop setup option."
            case .activeSession: return "Close the running session before preparing Steam's components."
            case .prefixMissing: return "Madeira could not prepare its Windows environment."
            }
        }
    }

    static func validPath(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count < 240,
              !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        return !name.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasSuffix(".") || $0.hasSuffix(" ") }
    }

    static func destination(_ relative: String, under drive: URL) throws -> URL {
        guard validPath(relative) else { throw Failure.conflict }
        let fm = FileManager.default
        var result = drive
        for component in relative.split(separator: "/") {
            if fm.fileExists(atPath: result.path) {
                let matches = try fm.contentsOfDirectory(atPath: result.path)
                    .filter { $0.caseInsensitiveCompare(String(component)) == .orderedSame }
                guard matches.isEmpty || matches == [String(component)] else { throw Failure.conflict }
            }
            result.appendPathComponent(String(component))
            guard result.standardizedFileURL.path == result.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw Failure.conflict
            }
        }
        return result
    }

    // Parse the central directory, then validate each local header. ZIP64,
    // encryption, symlinks and duplicate/case-colliding names are rejected.
    // Called only AFTER the whole archive's pinned SHA-256 has been checked.
    static func unpack(_ data: Data, write: (String, Data) throws -> Void) throws {
        func need(_ condition: Bool) throws { if !condition { throw Failure.invalidPackage } }
        try need(data.count >= 22 && data.count <= 64 * 1024 * 1024)
        func u16(_ p: Int) -> Int { Int(data[p]) | Int(data[p + 1]) << 8 }
        func u32(_ p: Int) -> Int { u16(p) | u16(p + 2) << 16 }
        guard let end = stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1)
            .first(where: { u32($0) == 0x06054b50 && $0 + 22 + u16($0 + 20) == data.count }) else {
            throw Failure.invalidPackage
        }
        let count = u16(end + 10), central = u32(end + 16), centralSize = u32(end + 12)
        try need(u16(end + 4) == 0 && u16(end + 6) == 0 && u16(end + 8) == count && count <= 256)
        try need(central <= end && centralSize == end - central)
        var cursor = central, total = 0
        var seen = Set<String>()
        for _ in 0..<count {
            try Task.checkCancellation()
            try need(cursor + 46 <= end && u32(cursor) == 0x02014b50)
            let flags = u16(cursor + 8), method = u16(cursor + 10)
            let crc = UInt32(u32(cursor + 16)), compressed = u32(cursor + 20), size = u32(cursor + 24)
            let nameLength = u16(cursor + 28), local = u32(cursor + 42)
            let next = cursor + 46 + nameLength + u16(cursor + 30) + u16(cursor + 32)
            let kind = (u32(cursor + 38) >> 16) & 0xf000
            try need(next <= end && flags & 1 == 0 && (method == 0 || method == 8))
            try need(kind == 0 || kind == 0x8000 || kind == 0x4000)
            guard let rawName = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8) else {
                throw Failure.invalidPackage
            }
            // Valve's Windows packages use backslashes. Normalize BEFORE all
            // traversal/duplicate checks, but compare local headers verbatim.
            let normalizedName = rawName.replacingOccurrences(of: "\\", with: "/")
            let directory = normalizedName.hasSuffix("/")
            let name = directory ? String(normalizedName.dropLast()) : normalizedName
            try need(validPath(name) && seen.insert(name.lowercased()).inserted)
            try need(size <= 64 * 1024 * 1024 && local + 30 <= central && u32(local) == 0x04034b50)
            try need(u16(local + 6) == flags && u16(local + 8) == method && u16(local + 26) == nameLength)
            let body = local + 30 + nameLength + u16(local + 28)
            try need(body <= central && compressed <= central - body)
            try need(data.subdata(in: local + 30..<local + 30 + nameLength) == Data(rawName.utf8))
            if flags & 8 == 0 { try need(u32(local + 18) == compressed && u32(local + 22) == size) }
            total += size
            try need(total <= 256 * 1024 * 1024)
            if directory { try need(size == 0 && compressed == 0); cursor = next; continue }
            let encoded = data.subdata(in: body..<body + compressed)
            var decoded: Data
            if method == 0 {
                try need(compressed == size); decoded = encoded
            } else {
                decoded = Data(count: max(size, 1))
                var stream = z_stream(), valid = false
                encoded.withUnsafeBytes { source in
                    decoded.withUnsafeMutableBytes { destination in
                        stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                        stream.avail_in = UInt32(compressed)
                        stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                        stream.avail_out = UInt32(max(size, 1))
                        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return }
                        let result = inflate(&stream, Z_FINISH)
                        valid = result == Z_STREAM_END && stream.total_in == compressed && stream.total_out == size
                        inflateEnd(&stream)
                    }
                }
                try need(valid); decoded.count = size
            }
            let actualCRC = decoded.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32(size)) }
            try need(UInt32(actualCRC) == crc)
            try write(name, decoded)
            cursor = next
        }
        try need(cursor == end)
    }

    // Only fixed client-discovery paths are written. Never write user IDs,
    // licenses, login cache, tokens, or a value asserting ownership.
    static func registry(_ text: String, machine: Bool) throws -> String {
        guard text.hasPrefix("WINE REGISTRY Version 2") else { throw Failure.prefixMissing }
        let root = windowsRoot.replacingOccurrences(of: "\\", with: "\\\\")
        let sections: [(String, [(String, String)])] = machine
            ? [("Software\\\\Valve\\\\Steam", [("InstallPath", root)]),
               ("Software\\\\Wow6432Node\\\\Valve\\\\Steam", [("InstallPath", root)])]
            : [("Software\\\\Valve\\\\Steam", [("SteamPath", root), ("SteamExe", root + "\\\\steam.exe")]),
               ("Software\\\\Valve\\\\Steam\\\\ActiveProcess",
                [("SteamClientDll", root + "\\\\steamclient.dll"), ("SteamClientDll64", root + "\\\\steamclient64.dll")])]
        var lines = text.components(separatedBy: "\n")
        for (key, values) in sections {
            let header = "[\(key)]"
            let starts = lines.indices.filter { lines[$0].lowercased().hasPrefix(header.lowercased()) }
            guard starts.count <= 1 else { throw Failure.conflict }
            if let start = starts.first {
                let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("[") } ?? lines.count
                var additions: [String] = []
                for (name, value) in values {
                    let prefix = "\"\(name)\"="
                    let matches = lines[(start + 1)..<end].filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
                    let expected = prefix + "\"\(value)\""
                    guard matches.isEmpty || matches == [expected] else { throw Failure.conflict }
                    if matches.isEmpty { additions.append(expected) }
                }
                lines.insert(contentsOf: additions, at: end)
            } else {
                lines += ["", header] + values.map { "\"\($0.0)\"=\"\($0.1)\"" } + [""]
            }
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(CryptoKit)
private final class SteamRuntimeRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let allowed = url?.scheme == "https" && url?.host == "client-update.akamai.steamstatic.com"
            && (url?.port == nil || url?.port == 443) && url?.user == nil && url?.password == nil
        completionHandler(allowed ? request : nil)
    }
}

actor SteamRuntimeInstaller {
    static let shared = SteamRuntimeInstaller()
    private var busy = false

    func prepareIfNeeded(prefix: URL, progress: @Sendable (String) async -> Void) async throws {
        let drive = prefix.appendingPathComponent("drive_c")
        let ready = SteamRuntimeFiles.criticalFileSHA256.allSatisfy { name, expected in
            guard let file = try? SteamRuntimeFiles.destination(SteamRuntimeFiles.relativeRoot + "/" + name, under: drive),
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
            return Self.hash(data) == expected
        }
        if ready { return }
        try await prepare(prefix: prefix, progress: progress)
    }

    // Runs before any Wine session in this app run; no Wine/JIT run.
    func prepare(prefix: URL, progress: @Sendable (String) async -> Void) async throws {
        guard !busy, wine_process_is_running() == 0, wineserver_is_running() == 0 else {
            throw SteamRuntimeFiles.Failure.activeSession
        }
        busy = true; defer { busy = false }
        let fm = FileManager.default
        // Do not let the template seeder overwrite a preexisting, unstamped
        // registry. Fresh downloads may have created drive_c/steamapps only.
        if !fm.fileExists(atPath: prefix.appendingPathComponent(".update-timestamp").path),
           ["system.reg", "user.reg"].contains(where: { fm.fileExists(atPath: prefix.appendingPathComponent($0).path) }) {
            throw SteamRuntimeFiles.Failure.conflict
        }
        let drive = prefix.appendingPathComponent("drive_c")
        let root = drive.appendingPathComponent(SteamRuntimeFiles.relativeRoot)
        guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw SteamRuntimeFiles.Failure.conflict
        }
        let stage = fm.temporaryDirectory.appendingPathComponent("madeira-runtime-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration, delegate: SteamRuntimeRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var names = Set<String>(), files: [String] = []
        for (index, package) in SteamRuntimeFiles.packages.enumerated() {
            try Task.checkCancellation()
            await progress("Downloading Steam components (\(index + 1) of \(SteamRuntimeFiles.packages.count))…")
            let url = URL(string: SteamRuntimeFiles.origin + package.file)!
            let (temporary, response) = try await session.download(from: url)
            defer { try? fm.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.host == url.host, http.url?.scheme == "https",
                  (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize == package.bytes else {
                throw SteamRuntimeFiles.Failure.invalidPackage
            }
            let archive = try Data(contentsOf: temporary, options: .mappedIfSafe)
            guard Self.hash(archive) == package.sha256 else { throw SteamRuntimeFiles.Failure.invalidPackage }
            await progress("Verifying Steam components…")
            try SteamRuntimeFiles.unpack(archive) { name, bytes in
                guard names.insert(name.lowercased()).inserted else { throw SteamRuntimeFiles.Failure.invalidPackage }
                let file = stage.appendingPathComponent(name)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: file, options: .atomic)
                files.append(name)
            }
        }
        guard Self.hash(try Data(contentsOf: stage.appendingPathComponent("steamclient64.dll"))) == SteamRuntimeFiles.clientSHA256,
              files.contains("steam.exe") else { throw SteamRuntimeFiles.Failure.invalidPackage }
        for name in ["steam.exe", "steamclient64.dll", "SDL3.dll", "video64.dll",
                     "libavcodec-62.dll", "libavfilter-11.dll", "libavformat-62.dll", "libavutil-60.dll",
                     "libswresample-6.dll", "libswscale-9.dll"] {
            guard SteamRuntimeFiles.isAMD64Image(try Data(contentsOf: stage.appendingPathComponent(name), options: .mappedIfSafe)) else {
                throw SteamRuntimeFiles.Failure.invalidPackage
            }
        }
        try Task.checkCancellation()
        guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw SteamRuntimeFiles.Failure.activeSession }
        await progress("Preparing the Windows environment…")
        try Task.checkCancellation()
        guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw SteamRuntimeFiles.Failure.activeSession }
        madeira_seed_prefix_if_needed(prefix.path)
        // Preflight all destinations and both hives before publishing anything.
        var pending: [(URL, Data)] = []
        for (file, machine) in [("system.reg", true), ("user.reg", false)] {
            let url = prefix.appendingPathComponent(file)
            guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw SteamRuntimeFiles.Failure.conflict
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            pending.append((url, Data(try SteamRuntimeFiles.registry(text, machine: machine).utf8)))
        }
        try Task.checkCancellation()
        // No suspension during publication; unknown files fail the entire preflight.
        try SteamRuntimeFiles.publish(stage: stage, drive: drive,
            backupRoot: prefix.appendingPathComponent(".madeira-steam-runtime-backup/jan2026"), names: files,
            hash: Self.hash, checkQuiescent: {
                try Task.checkCancellation()
                guard wine_process_is_running() == 0, wineserver_is_running() == 0 else { throw SteamRuntimeFiles.Failure.activeSession }
            }, beforeCommit: {
                for (url, bytes) in pending {
                    let backup = url.appendingPathExtension("dock-setup-bak")
                    if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: url, to: backup) }
                    try bytes.write(to: url, options: .atomic)
                }
            })
        await progress("Steam components are ready.")
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
