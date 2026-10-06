// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Madeira Dock for Ubisoft: drives dockhost-ubi.exe the way MadeiraDock
// drives dockhost.exe for Steam.
//
// Flow: the iOS app holds a valid Ubisoft session (UbisoftAuth), writes the
// one-use MUBI0001 handoff (session ticket + remember-me token + user ID +
// game ID), sets the MADEIRA_UBI_HOST_* environment, and starts Wine with
// dockhost-ubi.exe. The host ensures upc.exe is running and fires
// uplay://launch/{game_id}/{mode}. Progress is polled from the report file.
import Foundation

/// A Ubisoft game known to the Dock.
struct UbisoftDockGame {
    /// Ubisoft numeric game ID (e.g. "420" for Far Cry 4).
    var id: String
    /// Display name.
    var name: String
    /// 0 = singleplayer, 1 = multiplayer.
    var launchMode: Int = 0
}

enum UbisoftDockError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let s) = self { return s }
        return nil
    }
}

final class UbisoftDock {
    /// Parsed report fields from the host.
    struct Report {
        var fields: [String: Int] = [:]
        var terminalCode: Int? { fields["probe-result"] }
    }
    static var lastReport = Report()

    private static var drive: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MadeiraDockUbi", isDirectory: true)
    }
    private static var transferURL: URL? {
        drive.appendingPathComponent("launch-ubi.auth")
    }

    static func cleanup() {
        lastReport = Report()
        if let url = transferURL { try? FileManager.default.removeItem(at: url) }
        for key in ["MADEIRA_DOCK_AUTH_FILE", "MADEIRA_UBI_HOST_LAUNCH",
                    "MADEIRA_UBI_HOST_GAME_ID", "MADEIRA_UBI_HOST_LAUNCH_MODE",
                    "MADEIRA_UBI_HOST_CLIENT_DIR", "MADEIRA_UBI_HOST_LOG"] {
            unsetenv(key)
        }
    }

    // MARK: - Handoff (MUBI0001 envelope)

    private static func envelope(session: UbisoftSession, gameID: String) -> Data {
        var data = Data()
        data.append(contentsOf: "MUBI0001".utf8) // magic
        func append(_ s: String) {
            let bytes = Array(s.utf8)
            var len = UInt16(bytes.count).littleEndian
            data.append(Data(bytes: &len, count: 2))
            data.append(contentsOf: bytes)
        }
        // Order must match dock_ubi.h: ticket, remember-me, user ID, game ID.
        append(session.ticket)
        append(session.rememberMeTicket)
        append(session.userID)
        append(gameID)
        return data
    }

    /// Guest path for the handoff file inside the Wine prefix.
    private static func handoffGuestPath(_ url: URL) -> String {
        // Mirrors MadeiraDock.handoffGuestPath: \\?\unix\<host path>
        "\\\\?\\unix\\" + url.path
    }

    /// Writes the one-use transfer to protected Application Support storage
    /// and puts only its guest path in the environment.
    @MainActor static func writeHandoff(session: UbisoftSession, game: UbisoftDockGame) throws {
        cleanup()
        let report = drive.appendingPathComponent("madeira-dock-ubi.txt")
        if FileManager.default.fileExists(atPath: report.path) {
            try? FileManager.default.removeItem(at: report)
        }
        guard let url = transferURL else {
            throw UbisoftDockError.message("Ubisoft Dock's private transfer folder is unavailable.")
        }
        var data = envelope(session: session, gameID: game.id)
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        let fm = FileManager.default
        var folder = url.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700,
                                            .protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw UbisoftDockError.message("Madeira could not create Ubisoft Dock's private sign-in transfer.")
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            try file.write(contentsOf: data); try file.close()
            setenv("MADEIRA_DOCK_AUTH_FILE", handoffGuestPath(url), 1)
        } catch { try? file.close(); cleanup(); throw error }
    }

    // MARK: - Launch configuration

    /// The host's environment for the prepare phase. Call before the Steam
    /// Dock launch for Ubisoft games: this gets Connect running so the
    /// game's uplay_r1.dll DRM check passes when Steam starts the exe.
    static func configurePrepare() {
        setenv("MADEIRA_UBI_HOST_PREPARE", "1", 1)
        setenv("MADEIRA_UBI_HOST_CLIENT_DIR",
               "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher", 1)
        setenv("MADEIRA_UBI_HOST_LOG", "C:\\madeira-dock-ubi.txt", 1)
        setenv("MADEIRA_DOCK_SESSION", "1", 1)
    }

    /// The Wine command that starts the Ubisoft prepare host.
    /// Run this first; on probe-result=0 proceed with the Steam Dock launch.
    static var prepareCommand: (exe: String, args: String) {
        ("explorer.exe", "/desktop=madeira,1280x720 C:\\windows\\system32\\dockhost-ubi.exe")
    }

    // MARK: - Ubisoft game detection

    /// Known Ubisoft Steam app IDs (from the user's library; extend as found).
    /// These need Connect running even though Steam owns the license.
    static let knownUbisoftAppIDs: Set<Int> = [
        359550,  // Rainbow Six Siege
        323470,  // Ghost Recon Wildlands
        552520,  // Far Cry 5
        2379390, // R6 Siege Test Server
        812140,  // Assassin's Creed Odyssey
        911400,  // Assassin's Creed III Remastered
        326949,  // The Division PTS
        2146560, // The Outlast Trials
        220240,  // Far Cry 3
        304390,  // For Honor
        365590,  // The Division
    ]

    /// Heuristic: a Steam game needs Ubisoft Connect if its install dir
    /// contains uplay_r1.dll (the game-facing Ubisoft API) or its app ID is
    /// in the known list.
    static func needsUbisoftConnect(appID: Int, installPath: String) -> Bool {
        if knownUbisoftAppIDs.contains(appID) { return true }
        let fm = FileManager.default
        // Check the top level and one deep for the Ubisoft runtime DLL.
        let candidates = ["uplay_r1.dll", "uplay_r1_loader.dll", "uplay_r2.dll"]
        for dll in candidates {
            if fm.fileExists(atPath: (installPath as NSString).appendingPathComponent(dll)) {
                return true
            }
        }
        // One level deep (some games nest it in bin/).
        if let children = try? fm.contentsOfDirectory(atPath: installPath) {
            for child in children {
                let sub = (installPath as NSString).appendingPathComponent(child)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue else { continue }
                for dll in candidates {
                    if fm.fileExists(atPath: (sub as NSString).appendingPathComponent(dll)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Report polling

    /// Allowed report field names (mirrors the host's ubi_report calls).
    private static let allowed: Set<String> = [
        "host-start", "auth-consumed", "client-already-running",
        "client-starting", "client-running", "prepare-result", "probe-result",
    ]

    /// Reads new report fields. Call on the main actor, e.g. on a timer.
    @MainActor static func pollReport() -> Report {
        var report = lastReport
        let url = drive.appendingPathComponent("madeira-dock-ubi.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return report }
        for line in text.components(separatedBy: .newlines) {
            // "[ubi-host] <round> <field>=<number>"
            let parts = line.split(separator: " ")
            guard parts.count == 3, parts[0] == "[ubi-host]" else { continue }
            let kv = parts[2].split(separator: "=", maxSplits: 1)
            guard kv.count == 2, let value = Int(kv[1]) else { continue }
            let field = String(kv[0])
            guard allowed.contains(field) else { continue }
            report.fields[field] = value
        }
        lastReport = report
        return report
    }

    /// User-facing message for a terminal probe-result code.
    static func failureMessage(for code: Int) -> String {
        switch code {
        case 0: return "Ubisoft Connect is ready."
        case 30: return "Ubisoft Connect was not found. Install it via the Desktop session first."
        case 31: return "Could not start Ubisoft Connect."
        case 32: return "Ubisoft Connect did not start in time. Try launching it from the Desktop session once."
        default: return "Ubisoft Connect prepare failed (code \(code))."
        }
    }
}
