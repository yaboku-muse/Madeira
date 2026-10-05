// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 125hz
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import SwiftUI

// The starting screen of a game started through Madeira Dock (docs/MADEIRA_DOCK.md,
// "Starting screen"). A Dock start is a desktop session: explorer's virtual desktop
// runs the Dock host. The desktop's first GDI frame (explorer's own windows, the
// host's console window) used to end the starting screen, so the user watched the
// Wine desktop instead of the game. The starting screen now stays, with the Dock's
// status, until a window of the started game is up; a window that may need an answer
// reveals the desktop, and Show desktop reveals it on request.
//
// Which window is which comes from Winios.m's census (the owning program of every
// top-level window, with its executable path) and is decided by WHERE that program
// lives on drive C, never by its name:
//   - C:\windows\ holds Wine's own programs (shell, services, console hosts,
//     msiexec) and the Dock host: never the game;
//   - the Steam client's folder, outside its steamapps library, holds Valve's
//     client programs: a dialog of theirs may need the user;
//   - any other program is the game (or its own launcher) once the Dock host has
//     started. Before that, the game's one-time installs run from the batch, and a
//     window first shown then is an installer's: never the game, and a dialog of
//     theirs may need the user.
// Log tag: [steam-launch-view] (scene names, window sizes and owner classes only).

// MARK: - Rules (Foundation only; tests/host/check-dock-start-screen.py compiles this part)

/// One top-level window of a Dock start's Wine desktop, as Winios.m's census reports it.
/// `image`: the owning program's executable path, "" when it could not be read.
struct SteamLaunchWindow: Equatable {
    var image: String
    var width: Int
    var height: Int
    var visible: Bool
    /// The window put a frame on screen: GDI content, or a D3D swapchain of its own.
    var drawn: Bool
    var pid: UInt32 = 0
    var hwnd: UInt64 = 0
}

/// What a Dock start is showing.
enum SteamLaunchScene: Equatable {
    /// Nothing for the user yet; the host and Valve's client work in the background.
    case waiting
    /// A window that may need the user: a dialog of Valve's client or of a one-time installer.
    case steamWindow
    /// A window of the started game is up.
    case game

    var name: String {
        switch self {
        case .waiting: return "waiting"
        case .steamWindow: return "steam-window"
        case .game: return "game"
        }
    }

    enum Owner: String { case client = "steam-client", helper, other, unknown }

    /// Where programs live on drive C, lower case, each ending in a backslash.
    struct Places: Equatable {
        var windows: String
        var client: String
        var clientLibrary: String
        /// `clientRoot`: the Steam client's folder as a Windows path ("C:\Program Files (x86)\Steam").
        init(clientRoot: String, windows: String = "C:\\windows") {
            func folder(_ path: String) -> String {
                let p = SteamLaunchScene.path(path)
                return p.hasSuffix("\\") ? p : p + "\\"
            }
            self.windows = folder(windows)
            self.client = folder(clientRoot)
            self.clientLibrary = client + "steamapps\\"
        }
    }

    /// Smaller shown windows are tray lists, tool strips and caption fragments.
    static let gameMinimum = (width: 160, height: 120)
    static let dialogMinimum = (width: 240, height: 120)

    /// A Windows or NT path in the census's form: lower case, backslashes, no
    /// "\??\" or "\\?\" prefix.
    static func path(_ image: String) -> String {
        var p = image.lowercased().replacingOccurrences(of: "/", with: "\\")
        if p.hasPrefix("\\??\\") || p.hasPrefix("\\\\?\\") { p.removeFirst(4) }
        return p
    }

    static func owner(_ image: String, places: Places) -> Owner {
        let p = path(image)
        if p.isEmpty { return .unknown }
        if p.hasPrefix(places.windows) { return .helper }
        if p.hasPrefix(places.client) && !p.hasPrefix(places.clientLibrary) { return .client }
        return .other
    }

    /// `rendered`: D3D frames reached the screen since the start began. Stands in
    /// for a window whose owner could not be read, never for a known helper.
    /// `early`: windows first shown before the Dock host started (the one-time
    /// installs), which are never the game's. `installerReveal`: an early window's
    /// dialog may need the user. Returns the window that decided, for the log.
    static func decide(_ windows: [SteamLaunchWindow], rendered: Bool, places: Places,
                       early: Set<UInt64> = [], installerReveal: Bool = true) -> (scene: SteamLaunchScene, window: SteamLaunchWindow?) {
        var steam: SteamLaunchWindow?
        for window in windows where window.visible {
            let gameSized = window.width >= gameMinimum.width && window.height >= gameMinimum.height
            let dialogSized = window.width >= dialogMinimum.width && window.height >= dialogMinimum.height
            let installer = early.contains(window.hwnd)
            switch owner(window.image, places: places) {
            case .other where !installer && gameSized && (window.drawn || rendered): return (.game, window)
            case .unknown where !installer && gameSized && rendered: return (.game, window)
            case .client where steam == nil && window.drawn && dialogSized:
                steam = window
            // A one-time installer that fails can show an error box and wait for OK, and
            // the start waits for it. MADEIRA_DOCK_INSTALLER_REVEAL=0 keeps them hidden.
            case .other where installer && steam == nil && window.drawn && dialogSized && installerReveal:
                steam = window
            default: break
            }
        }
        return steam.map { (.steamWindow, $0) } ?? (.waiting, nil)
    }
}

/// Whether the starting screen covers the Wine desktop during a Dock start.
/// DockStartScreen feeds it the scene every 0.5 s. The game's window ends the
/// hold. A window that may need the user, shown for `revealDelay` s, reveals the
/// desktop (when auto-reveal is on); once it has been gone for `coverDelay` s the
/// starting screen returns, at most `maxAutoReveals` times, after which the
/// desktop stays. Show desktop reveals it for good.
struct SteamLaunchHold {
    enum Action: Equatable { case none, showGame, reveal, cover }
    static let revealDelay = 2.0, coverDelay = 4.0, maxAutoReveals = 6
    let autoReveal: Bool
    private(set) var scene = SteamLaunchScene.waiting
    private(set) var revealed = false
    private(set) var manual = false
    private(set) var finished = false
    private(set) var autoReveals = 0
    private var steamSince: Double?
    private var clearSince: Double?

    init(autoReveal: Bool) { self.autoReveal = autoReveal }

    /// A window that may need the user is up and the starting screen still hides it.
    var needsAttention: Bool { !finished && !revealed && scene == .steamWindow }

    mutating func step(_ next: SteamLaunchScene, now: Double) -> Action {
        guard !finished else { return .none }
        scene = next
        switch next {
        case .game:
            finished = true
            return .showGame
        case .steamWindow:
            clearSince = nil
            let since = steamSince ?? now
            steamSince = since
            guard autoReveal, !revealed, autoReveals < Self.maxAutoReveals, now - since >= Self.revealDelay else { return .none }
            revealed = true
            autoReveals += 1
            return .reveal
        case .waiting:
            steamSince = nil
            guard revealed, !manual, autoReveals < Self.maxAutoReveals else { clearSince = nil; return .none }
            let since = clearSince ?? now
            clearSince = since
            guard now - since >= Self.coverDelay else { return .none }
            revealed = false
            clearSince = nil
            return .cover
        }
    }

    /// The user asked to see the desktop: shown at once, and never covered again.
    /// Returns false when it is already shown that way.
    mutating func showDesktop() -> Bool {
        guard !finished, !manual else { return false }
        revealed = true
        manual = true
        return true
    }
}

/// A bounded diagnostic from the loader's explicit rejection records. Optional
/// DLL rejection is evidence to display after a stall, not a launch failure.
struct SteamLoaderRejection: Equatable {
    let module: String
    let phase: String
    let status: String?
    let fileMachine: String?
    let currentMachine: String?

    private static let record = try! NSRegularExpression(pattern:
        #"\[pe-image\] (section|architecture|map|module setup|PE64 conversion) rejected L?"([^"\r\n]*)" (.*)$"#)
    private static let resolutionRecord = try! NSRegularExpression(pattern:
        #"\[dll-missing\] (?:ml718 UNCAPPED|rev=ml336 #[0-9]+) L?"([^"\r\n]*)" (.*)$"#)

    static func parse(_ raw: String) -> Self? {
        guard raw.utf8.count <= 4096 else { return nil }
        var raw = raw
        // Native callbacks can include one line terminator; file-tail records do not.
        // Swift treats CRLF as a single Character, so remove one terminator.
        if raw.hasSuffix("\r\n") || raw.hasSuffix("\n") || raw.hasSuffix("\r") { raw.removeLast() }
        guard !raw.contains("\n"), !raw.contains("\r") else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        let match: NSTextCheckingResult
        let phase: String, moduleIndex: Int, detailIndex: Int
        if raw.contains("[pe-image]"), let rejected = record.firstMatch(in: raw, range: range) {
            match = rejected
            phase = String(raw[Range(match.range(at: 1), in: raw)!])
            moduleIndex = 2; detailIndex = 3
        } else if raw.contains("[dll-missing]"), let missing = resolutionRecord.firstMatch(in: raw, range: range) {
            match = missing
            phase = "dependency resolution"
            moduleIndex = 1; detailIndex = 2
        } else { return nil }
        func part(_ index: Int) -> String { String(raw[Range(match.range(at: index), in: raw)!]) }
        let module = part(moduleIndex).replacingOccurrences(of: "/", with: "\\").split(separator: "\\").last.map(String.init) ?? ""
        guard !module.isEmpty, module.utf8.count <= 128,
              module.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
              [".dll", ".exe"].contains(where: { module.lowercased().hasSuffix($0) }) else { return nil }
        let tokens = part(detailIndex).split(separator: " ")
        func hex(_ key: String, digits: Int) -> String? {
            let values = tokens.filter { $0.hasPrefix(key + "=") }
            guard values.count == 1 else { return nil }
            let value = values[0].dropFirst(key.count + 1)
            guard value.count == digits, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            return value.uppercased()
        }
        let status = hex("status", digits: 8)
        let file = hex("file_machine", digits: 4), current = hex("current_machine", digits: 4)
        guard phase == "architecture" ? file != nil && current != nil : status != nil else { return nil }
        if phase == "dependency resolution", status == "00000000" { return nil }
        return Self(module: module, phase: phase, status: status, fileMachine: file, currentMachine: current)
    }

    var text: String {
        let detail = status.map { "status 0x" + $0 } ?? "file machine 0x\(fileMachine ?? "?"); current machine 0x\(currentMachine ?? "?")"
        return "Last observed loader rejection: \(module), \(phase), \(detail)."
    }
}

/// Successful NtCreateUserProcess evidence for the selected launch executable.
/// Retains only a basename and IDs after comparing the complete image identity.
struct SteamExecutableCreation: Equatable {
    let module: String
    let pid: UInt32
    let tid: UInt32
    let generation: UInt64?

    private static let record = try! NSRegularExpression(pattern:
        #"^\[process-created\] pid=([0-9a-fA-F]{8}) tid=([0-9a-fA-F]{8}) status=00000000 (?:generation=([0-9a-fA-F]{16}) )?image_utf16=([0-9a-fA-F]{4,2048})$"#)

    static func parse(_ line: String, expectedImage: String) -> Self? {
        guard line.utf8.count <= 4096 else { return nil }
        var line = line
        if line.hasSuffix("\r\n") || line.hasSuffix("\r") || line.hasSuffix("\n") { line.removeLast() }
        guard !line.contains("\r"), !line.contains("\n") else { return nil }
        guard let match = record.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        func part(_ n: Int) -> String { String(line[Range(match.range(at: n), in: line)!]) }
        guard let pid = UInt32(part(1), radix: 16), pid != 0,
              let tid = UInt32(part(2), radix: 16), tid != 0 else { return nil }
        let generation = match.range(at: 3).location == NSNotFound ? nil : UInt64(part(3), radix: 16)
        let hex = Array(part(4).utf8)
        guard hex.count % 4 == 0 else { return nil }
        var units: [UInt16] = []
        for offset in stride(from: 0, to: hex.count, by: 4) {
            guard let unit = UInt16(String(decoding: hex[offset..<offset + 4], as: UTF8.self), radix: 16) else { return nil }
            units.append(unit)
        }
        // Do not silently repair malformed UTF-16 into an executable identity.
        let image = String(decoding: units, as: UTF16.self)
        guard Array(image.utf16) == units else { return nil }
        func identity(_ value: String) -> String? {
            let path = SteamLaunchScene.path(value)
            let chars = Array(path.utf8)
            guard chars.count >= 4, (97...122).contains(chars[0]), chars[1] == 58, chars[2] == 92,
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  path.hasSuffix(".exe") else { return nil }
            let components = path.split(separator: "\\", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
            return path
        }
        guard let actual = identity(image), let expected = identity(expectedImage), actual.utf16.elementsEqual(expected.utf16),
              let module = image.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").last.map(String.init),
              module.utf8.count <= 128 else { return nil }
        return Self(module: module, pid: pid, tid: tid, generation: generation == 0 ? nil : generation)
    }

    var text: String { "Selected executable created: \(module) (PID 0x\(String(pid, radix: 16)))." }
}

/// Native child teardown evidence. Unix exit codes are never interpreted as
/// Windows exception codes; PID and birth generation must both match.
struct SteamProcessExit: Equatable {
    let pid: UInt32
    let generation: UInt64
    let windowsStatus: Bool
    let status: UInt32

    private static let record = try! NSRegularExpression(pattern:
        #"^\[process-exited\] pid=([0-9a-fA-F]{8}) generation=([0-9a-fA-F]{16}) status_kind=(windows|unix) status=([0-9a-fA-F]{8})$"#)

    static func parse(_ line: String) -> Self? {
        guard line.utf8.count <= 256 else { return nil }
        var line = line
        if line.hasSuffix("\r\n") || line.hasSuffix("\r") || line.hasSuffix("\n") { line.removeLast() }
        guard !line.contains("\r"), !line.contains("\n"),
              let match = record.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        func part(_ n: Int) -> String { String(line[Range(match.range(at: n), in: line)!]) }
        guard let pid = UInt32(part(1), radix: 16), pid != 0,
              let generation = UInt64(part(2), radix: 16), generation != 0,
              let status = UInt32(part(4), radix: 16) else { return nil }
        return Self(pid: pid, generation: generation, windowsStatus: part(3) == "windows", status: status)
    }

    var reportsFault: Bool {
        windowsStatus && [UInt32(0xc0000005), 0xc000001d, 0xc0000094, 0xc0000095,
                          0xc0000096, 0xc00000fd, 0xc0000409].contains(status)
    }
    func matches(_ creation: SteamExecutableCreation?) -> Bool {
        creation?.pid == pid && creation?.generation == generation
    }
    var statusText: String {
        "\(windowsStatus ? "Windows" : "Unix") status 0x\(String(format: "%08x", status))"
    }
}

/// Tracks only the exact selected image and Dock's actual host image. Steam's
/// client DLL runs inside dockhost.exe; unrelated helper exits are not host exits.
struct SteamLaunchLifetime {
    private(set) var gameCreation: SteamExecutableCreation?
    private(set) var hostCreation: SteamExecutableCreation?
    private(set) var gameExit: SteamProcessExit?
    private(set) var hostExit: SteamProcessExit?
    private var exits: [SteamProcessExit] = []
    let expectedGame: String?
    let expectedHost: String

    init(expectedGame: String?, expectedHost: String) {
        self.expectedGame = expectedGame; self.expectedHost = expectedHost
    }

    private func newer(_ creation: SteamExecutableCreation, than current: SteamExecutableCreation?) -> Bool {
        guard let current else { return true }
        if let previous = current.generation { return (creation.generation ?? 0) > previous }
        return creation != current
    }

    mutating func consume(_ line: String) {
        if line.hasPrefix("[process-created]") {
            if let expectedGame, let creation = SteamExecutableCreation.parse(line, expectedImage: expectedGame), newer(creation, than: gameCreation) {
                gameCreation = creation
                gameExit = exits.last { $0.matches(creation) }
            }
            if let creation = SteamExecutableCreation.parse(line, expectedImage: expectedHost), newer(creation, than: hostCreation) {
                hostCreation = creation
                hostExit = exits.last { $0.matches(creation) }
            }
        } else if let exit = SteamProcessExit.parse(line), !exits.contains(exit) {
            // An immediately exiting child can publish before its parent's
            // successful creation acknowledgement. Keep a bounded recent cache.
            exits.append(exit)
            if exit.matches(gameCreation) { gameExit = exit }
            if exit.matches(hostCreation) { hostExit = exit }
            if exits.count > 256 { exits.removeFirst(exits.count - 256) }
        }
    }
}

/// Recoverable inactivity warnings based on evidence, not on retry counters.
/// A Steam running flag is not proof that an executable or render window exists.
struct SteamLaunchProgress {
    enum Stage: String {
        case starting, signingIn, authenticated, authorized, content, configuration
        case requested, executableCreated, programObserved, rendered, exited, hostEnded, hostFailed, steamCrashed

        var timeout: Double? {
            switch self {
            case .starting: return 60
            case .signingIn, .authenticated: return 120
            case .authorized, .configuration, .requested, .executableCreated, .programObserved: return 180
            case .content: return 600
            case .rendered, .exited, .hostEnded, .hostFailed, .steamCrashed: return nil
            }
        }
    }
    private(set) var stage = Stage.starting
    private(set) var since = 0.0
    private var lastTime = 0.0

    init(startedAt: Double = 0) {
        if startedAt.isFinite && startedAt >= 0 { since = startedAt; lastTime = startedAt }
    }

    mutating func step(_ fields: [String: String], programObserved: Bool, rendered: Bool,
                       now: Double, executableCreated: Bool = false,
                       gameExit: SteamProcessExit? = nil, hostExit: SteamProcessExit? = nil) -> Bool {
        guard now.isFinite, now >= lastTime else { return false }
        lastTime = now
        let next: Stage
        if fields["probe-result"] != nil { next = .hostEnded }
        else if let hostExit { next = hostExit.reportsFault ? .steamCrashed : hostExit.status == 0 ? .hostEnded : .hostFailed }
        else if gameExit != nil { next = .exited }
        else if fields["launch-game-ended"] == "1" { next = .exited }
        else if rendered { next = .rendered }
        else if programObserved { next = .programObserved }
        else if executableCreated { next = .executableCreated }
        else if fields["launch-update-wait"] != nil && fields["launch-update-ready"] == nil { next = .content }
        else if fields["launch-config-wait"] != nil && ["22", "23"].contains(fields["launch-client-error"] ?? "") { next = .configuration }
        else if fields["launch-request-submitted"] == "1" || fields["launch-client-error"] == "0" || fields["launch-game-running"] == "1" { next = .requested }
        else if fields["session-requested-app-listed"] == "1" { next = .authorized }
        else if fields["session-authenticated-online"] == "1" { next = .authenticated }
        else if fields["session-native-token-submitted"] != nil || fields["session-logon-start-result"] != nil { next = .signingIn }
        else { next = .starting }
        guard next != stage else { return false }
        stage = next; since = now
        return true
    }

    func warning(now: Double) -> String? {
        guard now.isFinite, now >= lastTime, let timeout = stage.timeout, now - since >= timeout else { return nil }
        let reason: String
        switch stage {
        case .content: reason = "Steam has not reported the required content ready."
        case .configuration: reason = "Steam has not finished loading the game's configuration."
        case .requested: reason = "Steam received the launch request, but no game or launcher window has been observed."
        case .programObserved: reason = "A game or launcher process has a window, but no game frame has been observed."
        case .executableCreated: reason = "The selected executable was created, but no game or launcher window has been observed."
        case .authorized: reason = "The license is confirmed, but Steam has not accepted the launch."
        case .authenticated: reason = "Steam signed in, but has not confirmed the game's license."
        case .signingIn: reason = "Steam has not confirmed sign-in."
        case .starting: reason = "Steam startup has not advanced."
        case .rendered, .exited, .hostEnded, .hostFailed, .steamCrashed: return nil
        }
        return reason + " This stage has taken \(Int(now - since)) seconds. Show desktop to check for a prompt, or export the diagnostic log."
    }
}

/// The starting screen's text for a Dock start, from the host's numeric report.
/// The host writes its fields as it goes (madeira-dock src/main.c,
/// session.c, launch.c), and the text follows the furthest stage reported: the
/// host started (probe-start-bits), the sign-in submitted, signed in, the game's
/// license confirmed, the game's executable prepared (only for a game that needs
/// it) and Steam's launch accepted (launch-client-error=0). Steam's own waits
/// (content, configuration, another session) come first.
enum DockStartStatus {
    /// Seconds without the host's first field before the text says it is late.
    static let slowAfter = 30.0

    /// What the start is doing. `installers`: this start runs the game's one-time
    /// installs first; `installerProgress`: their progress in words;
    /// `installsFinished`: they ended, and the host starts next. `waited`: seconds
    /// since the host could start (the start began, or the installs finished); it
    /// only matters before the host's first field.
    static func text(_ fields: [String: String], installers: Bool, installerProgress: String?,
                     installsFinished: Bool, waited: Double) -> String {
        if fields["launch-update-wait"] != nil && fields["launch-update-ready"] == nil {
            return "Steam is installing content this game needs. The game starts when it finishes…"
        }
        // Steam still counts an earlier session as playing (error 35); the Dock asks again.
        if fields["launch-session-wait"] != nil && fields["launch-client-error"] == "35" {
            return "Steam says this account is still playing in another session. Waiting for Steam to end it (up to 3 minutes)…"
        }
        // Right after sign-in Steam may not have the game's configuration yet (22, 23); the Dock asks again.
        if fields["launch-config-wait"] != nil && (fields["launch-client-error"] == "22" || fields["launch-client-error"] == "23") {
            return "Steam is still loading this game's configuration. Waiting for it…"
        }
        if fields["launch-client-error"] == "0" { return "The game is starting. Waiting for its window…" }
        if ["ceg-scm", "ceg-request-busy", "ceg-request"].contains(where: { fields[$0] != nil }) && fields["ceg-result"] == nil {
            return "Steam is preparing this game's executable…"
        }
        if fields["session-requested-app-listed"] == "1" { return "License confirmed. Steam is starting the game…" }
        if fields["session-authenticated-online"] == "1" { return "Signed in. Waiting for Steam to confirm this game's license…" }
        if fields["session-native-token-submitted"] != nil || fields["session-logon-start-result"] != nil {
            return "Signing in to Steam…"
        }
        if hostStarted(fields) { return "Loading Steam…" }
        // Before the host's first field: the one-time installs run first, then the host starts.
        let starting = waited >= slowAfter ? "Still starting Madeira Dock…" : "Starting Madeira Dock…"
        guard installers else { return starting }
        guard installsFinished else { return installerProgress ?? "Running this game's one-time installs…" }
        return (installerProgress ?? "One-time installs finished.") + "\n" + starting
    }

    /// The host has started (its first report field): the one-time installs are over.
    static func hostStarted(_ fields: [String: String]) -> Bool { fields["probe-start-bits"] != nil }

    /// The host reported a result. The host waits for the game it started, so a
    /// result while the starting screen is up means no game window appeared; any
    /// non-zero result is a failure too. nil when the start goes on.
    static func failure(result: Int?, words: String?, launching: Bool) -> String? {
        guard let result, launching || result != 0 else { return nil }
        return words ?? "Madeira Dock exited before a game window appeared. Export the diagnostic log."
    }
}

// MARK: - Model

extension SteamLaunchScene.Places {
    /// Madeira's Wine prefix: C:\windows and the Steam client Madeira Dock drives.
    static var standard: Self { Self(clientRoot: SteamRuntimeFiles.windowsRoot) }
}

/// A Dock start's starting screen: LibraryModel calls begin, poll and finish, and
/// LibraryHUD shows what it publishes. Like LibraryModel, it is used on the main
/// thread only (the session timer and the views).
final class DockStartScreen: ObservableObject {
    static let shared = DockStartScreen()

    /// A Dock start's session runs (the status line, a failure and its Close session).
    @Published private(set) var active = false
    /// The started game's App ID, for its artwork.
    @Published private(set) var appID: Int?
    /// Why the start stopped (the host's report in words); the starting screen stays.
    @Published private(set) var failure: String?
    /// The starting screen holds the desktop back and offers Show desktop.
    @Published private(set) var holding = false
    /// A window that may need the user is up behind the starting screen.
    @Published private(set) var attention = false
    @Published private(set) var progressWarning: String?
    @Published private(set) var loaderDiagnostic: String?
    @Published private(set) var executableStatus: String?

    private var hold: SteamLaunchHold?
    private var progress = SteamLaunchProgress()
    private var sceneLines = 0
    private var early = Set<UInt64>()
    private var hostStarted = false
    private var exitObserved = false
    private var started = Date()
    private let places = SteamLaunchScene.Places.standard

    /// A library session begins; `game` is set for a Dock start.
    func begin(_ game: DockGame?, at start: Date) {
        endHold(reason: nil)
        active = game != nil; appID = game?.id; failure = nil
        progress = SteamLaunchProgress(); progressWarning = nil
        loaderDiagnostic = nil; LogStore.shared.resetLaunchRejection()
        executableStatus = nil
        LogStore.shared.trackLaunchExecutable(game == nil ? nil : MadeiraDock.launchImage)
        exitObserved = false; hostStarted = false; early = []; started = start
        guard let game, MadeiraConfig.flag("MADEIRA_DOCK_HIDE_DESKTOP") else { return }   // 0: a Dock start's starting screen ends on the desktop's first frame, as before
        LogStore.shared.setLaunchDiagnosticsActive(true)
        let hold = SteamLaunchHold(autoReveal: MadeiraConfig.flag("MADEIRA_DOCK_AUTO_REVEAL"))   // 0: a window that may need the user never reveals the desktop by itself (Show desktop still does)
        self.hold = hold; sceneLines = 0; holding = true
        winios_window_census_enable(1)
        LogStore.shared.log("[steam-launch-view] hold app=\(game.id) auto-reveal=\(hold.autoReveal ? 1 : 0)")
    }

    /// The session ended.
    func finish() {
        endHold(reason: "session-ended")
        active = false; appID = nil; failure = nil
        progressWarning = nil
        loaderDiagnostic = nil
        executableStatus = nil; LogStore.shared.trackLaunchExecutable(nil)
        LogStore.shared.setLaunchDiagnosticsActive(false)
    }

    /// Every 0.5 s from LibraryModel.poll while a session runs. `rendered`: D3D
    /// frames reached the screen since the start began.
    func poll(_ model: LibraryModel, rendered: Bool) {
        guard active else { return }
        let diagnostic = LogStore.shared.launchRejection?.text
        if loaderDiagnostic != diagnostic { loaderDiagnostic = diagnostic }
        let elapsed = Date().timeIntervalSince(started)
        var report: MadeiraDock.Report?
        // The host's result: a start that stopped keeps the starting screen with the report's words.
        if !exitObserved && MadeiraConfig.flag("MADEIRA_DOCK_STATUS") {   // 0: the starting screen does not watch the host's result
            let current = MainActor.assumeIsolated { MadeiraDock.pollReport() }
            report = current
            if current.result != nil {
                exitObserved = true
                if let words = DockStartStatus.failure(result: current.result, words: current.failure, launching: model.launching) {
                    failure = words
                    LogStore.shared.log("[dock-status] host-ended result=\(current.result ?? 0) starting=\(model.launching ? 1 : 0)", level: .error)
                    MainActor.assumeIsolated { MadeiraDock.cleanup() }
                }
            }
        }
        let lifetime = LogStore.shared.launchLifetime
        let creation = lifetime?.gameCreation
        let fields = (report ?? MainActor.assumeIsolated { MadeiraDock.pollReport() }).fields
        let endedStatus: String?
        if let exit = lifetime?.hostExit, fields["probe-result"] == nil {
            endedStatus = "Steam host \(exit.reportsFault ? "reported a crash" : "exited"): \(exit.statusText)."
        } else if let exit = lifetime?.gameExit, let creation {
            endedStatus = "Selected executable exited: \(creation.module), \(exit.statusText)."
        } else { endedStatus = nil }
        if lifetime?.gameExit != nil || lifetime?.hostExit != nil {
            if progress.step(fields, programObserved: false, rendered: false, now: elapsed,
                             gameExit: lifetime?.gameExit, hostExit: lifetime?.hostExit) {
                LogStore.shared.log("[steam-launch-stage] stage=\(progress.stage.rawValue) t=\(Int(elapsed))s")
            }
            if executableStatus != endedStatus { executableStatus = endedStatus }
        }
        guard var hold else { return }
        if !hostStarted {
            hostStarted = DockStartStatus.hostStarted((report ?? MainActor.assumeIsolated { MadeiraDock.pollReport() }).fields)
            if hostStarted { progress = SteamLaunchProgress(startedAt: elapsed) }
        }
        let windows = Self.censusWindows()
        // Windows shown before the host started belong to the one-time installs.
        if !hostStarted { for window in windows where window.visible { early.insert(window.hwnd) } }
        let installerReveal = MadeiraConfig.flag("MADEIRA_DOCK_INSTALLER_REVEAL")   // 0: a one-time installer's dialog never reveals the desktop by itself
        let decision = SteamLaunchScene.decide(windows, rendered: rendered, places: places, early: early, installerReveal: installerReveal)
        // The census proves that a program owns a window. A launcher may be that
        // program; do not treat Steam's running bit as proof of game creation.
        let programObserved = hostStarted && windows.contains {
            !early.contains($0.hwnd) && SteamLaunchScene.owner($0.image, places: places) == .other
        }
        if progress.step(fields, programObserved: programObserved, rendered: decision.scene == .game, now: elapsed,
                         executableCreated: hostStarted && creation != nil,
                         gameExit: lifetime?.gameExit, hostExit: lifetime?.hostExit) {
            LogStore.shared.log("[steam-launch-stage] stage=\(progress.stage.rawValue) t=\(Int(elapsed))s")
        }
        let warning = hostStarted ? progress.warning(now: elapsed) : nil
        if progressWarning != warning { progressWarning = warning }
        let status: String?
        if let endedStatus {
            status = endedStatus
        } else {
            status = progress.stage == .executableCreated ? creation.map { $0.text + " Waiting for a game or launcher window." } : nil
        }
        if executableStatus != status { executableStatus = status }
        if decision.scene != hold.scene, sceneLines < 24 {
            sceneLines += 1
            let window = decision.window.map {
                " window=\($0.width)x\($0.height) owner=\(SteamLaunchScene.owner($0.image, places: places).rawValue)" +
                    (early.contains($0.hwnd) ? "-installer" : "") + " pid=\(String($0.pid, radix: 16))"
            } ?? ""
            LogStore.shared.log("[steam-launch-view] scene=\(decision.scene.name) shown=\(windows.filter(\.visible).count)\(window) t=\(Int(elapsed))s")
        }
        let action = hold.step(decision.scene, now: elapsed)
        self.hold = hold
        switch action {
        case .none:
            break
        case .showGame:
            endHold(reason: "game-window")
            if model.launching { model.showGameView(reason: "game-window") }
            return
        case .reveal:
            LogStore.shared.log("[steam-launch-view] reveal reason=steam-window count=\(hold.autoReveals) t=\(Int(elapsed))s")
            if model.launching { model.showGameView(reason: "steam-window") }
        case .cover:
            // The window was answered; back to the starting screen.
            LogStore.shared.log("[steam-launch-view] cover reason=steam-window-closed t=\(Int(elapsed))s")
            LibraryKeyboard.hide(); model.menu = false
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.launching = true }
        }
        if attention != hold.needsAttention { attention = hold.needsAttention }
    }

    /// Show desktop on the starting screen: the desktop stays until the game's window is up.
    func showDesktop(_ model: LibraryModel) {
        guard var hold, hold.showDesktop() else { return }
        self.hold = hold
        attention = false
        LogStore.shared.log("[steam-launch-view] reveal reason=button scene=\(hold.scene.name) t=\(Int(Date().timeIntervalSince(started)))s")
        model.showGameView(reason: "show-desktop")
    }

    private func endHold(reason: String?) {
        guard hold != nil || holding else { return }
        LogStore.shared.setLaunchDiagnosticsActive(false)
        if let reason, let hold {
            LogStore.shared.log("[steam-launch-view] end reason=\(reason) scene=\(hold.scene.name) revealed=\(hold.revealed ? 1 : 0) t=\(Int(Date().timeIntervalSince(started)))s")
        }
        hold = nil
        holding = false; attention = false
        winios_window_census_enable(0)
    }

    /// Winios.m's census as SteamLaunchScene reads it.
    private static func censusWindows() -> [SteamLaunchWindow] {
        var raw = [winios_census_window](repeating: winios_census_window(), count: Int(WINIOS_CENSUS_MAX))
        let count = Int(winios_window_census(&raw, Int32(raw.count)))
        return raw.prefix(max(0, min(count, raw.count))).map { window in
            let image = withUnsafeBytes(of: window.image) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
            return SteamLaunchWindow(image: image, width: Int(window.w), height: Int(window.h), visible: window.visible != 0,
                                     drawn: window.presents > 0 || window.metal != 0, pid: window.pid, hwnd: window.hwnd)
        }
    }
}

/// The started game's Steam artwork as the starting screen's backdrop: the wide
/// library hero, else the cover (public store artwork by App ID, no account data).
struct SteamLaunchBackdrop: View {
    let appID: Int
    @State private var useCover = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                AsyncImage(url: useCover ? SteamGamesRules.cover(appID) : Self.hero(appID)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    case .failure:
                        Color.clear.onAppear { useCover = true }
                    default:
                        Color.clear
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .accessibilityHidden(true)
    }

    static func hero(_ appID: Int) -> URL? {
        guard appID > 0 else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_hero.jpg")
    }
}
