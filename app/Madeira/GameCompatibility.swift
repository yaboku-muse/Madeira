// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Evidence-backed policies, separate from import-derived graphics badges.
/// Unknown applications use the generic launch path. Each adapter owns only
/// its documented settings, rather than supplying guessed command-line flags.
struct GameCompatibilityProfile: Equatable {
    enum Renderer: String { case d3d11, d3d12 }
    enum SettingsAdapter { case teardownRegistry }
    let appID: Int
    let revision: Int
    let preferredRenderer: Renderer
    let settingsAdapter: SettingsAdapter

    static func resolve(appID: Int, enabled: Bool = true) -> Self? {
        guard enabled else { return nil }
        return builtins.first { $0.appID == appID }
    }

    // Teardown 2.1.0: supplied options.xml and a real D3D12 device trace.
    // No profile is needed for PEAK's ordinary D3D11 launch path.
    private static let builtins = [Self(appID: 1167630, revision: 1,
        preferredRenderer: .d3d12, settingsAdapter: .teardownRegistry)]

    func prepare(options: URL) throws -> Bool {
        switch settingsAdapter {
        case .teardownRegistry: return try TeardownRendererSettings.prepare(file: options)
        }
    }

    func settingsFile(userFolder: URL) -> URL {
        switch settingsAdapter {
        case .teardownRegistry: return userFolder.appendingPathComponent("AppData/Local/Teardown/options.xml")
        }
    }
}

/// Edits the two known graphics values without reserializing other options.
/// Unknown versions, duplicate/ambiguous nodes, entities, and malformed XML
/// are refused. No save, display, audio, or input setting is synthesized.
enum TeardownRendererSettings {
    enum Failure: Error, LocalizedError {
        case unsupported, changed, unsafePath
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Teardown renderer settings have an unsupported format. The original file was preserved."
            case .changed: return "Teardown settings changed while preparing the renderer. Try starting again."
            case .unsafePath: return "Teardown settings resolve outside the game settings folder. The original file was preserved."
            }
        }
    }

    private final class Schema: NSObject, XMLParserDelegate {
        var path: [String] = []
        var valid = true
        var ended = false
        var counts: [String: Int] = [:]
        var rendererNodes = 0
        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            path.append(name)
            let key = path.joined(separator: "/")
            counts[key, default: 0] += 1
            if name == "gfxapi" || name == "d3d12support" { rendererNodes += 1 }
            if path.count == 1 {
                valid = valid && name == "registry" && attributes == ["version": "2.1.0"]
            }
            if key == "registry/options/gfx/gfxapi" || key == "registry/options/gfx/d3d12support" {
                valid = valid && attributes.count == 1 && ["0", "1"].contains(attributes["value"] ?? "")
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) { _ = path.popLast() }
        func parserDidEndDocument(_ parser: XMLParser) { ended = true }
        func parser(_ parser: XMLParser, parseErrorOccurred error: Error) { valid = false }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if path.last == "gfxapi" || path.last == "d3d12support" {
                valid = valid && string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    static func selectingD3D12(_ data: Data) throws -> Data {
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8),
              !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY"),
              !text.contains("<![CDATA[") else { throw Failure.unsupported }
        let schema = Schema(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = schema
        guard parser.parse(), parser.parserError == nil, schema.valid, schema.ended,
              schema.path.isEmpty, schema.rendererNodes == 2,
              ["registry", "registry/options", "registry/options/gfx",
               "registry/options/gfx/gfxapi", "registry/options/gfx/d3d12support"]
                .allSatisfy({ schema.counts[$0] == 1 }) else { throw Failure.unsupported }
        let source = text as NSString
        let ignoredPattern = try NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<\?[\s\S]*?\?>"#)
        let withoutIgnoredMarkup = ignoredPattern.stringByReplacingMatches(in: text,
            range: NSRange(location: 0, length: source.length), withTemplate: "")
        var edits: [NSRange] = []
        for node in ["gfxapi", "d3d12support"] {
            let pattern = "<" + node + #"\s+value\s*=\s*(["'])([01])\1\s*/>"#
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            // A matching-looking comment or a second node is ambiguous: no edit.
            guard matches.count == 1, regex.numberOfMatches(in: withoutIgnoredMarkup,
                range: NSRange(location: 0, length: (withoutIgnoredMarkup as NSString).length)) == 1 else {
                throw Failure.unsupported
            }
            edits.append(matches[0].range(at: 2))
        }
        let result = NSMutableString(string: text)
        for range in edits.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: range, with: "1")
        }
        return Data((result as String).utf8)
    }

    /// Called only while Wine is stopped. Keep the original alongside the
    /// settings, and refuse symbolic links instead of editing another prefix.
    static func prepare(file: URL) throws -> Bool {
        let fm = FileManager.default
        let parent = file.deletingLastPathComponent()
        guard parent.standardizedFileURL == parent.resolvingSymlinksInPath().standardizedFileURL,
              file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else {
            throw Failure.unsafePath
        }
        // Missing settings use the game's D3D12 default. Do not invent a
        // versioned registry before the engine has created its own file.
        guard fm.fileExists(atPath: file.path) else { return false }
        let original = try Data(contentsOf: file)
        let updated = try selectingD3D12(original)
        guard updated != original else { return false }
        let backup = parent.appendingPathComponent("options.xml.madeira-renderer-backup")
        guard backup.standardizedFileURL == backup.resolvingSymlinksInPath().standardizedFileURL else {
            throw Failure.unsafePath
        }
        if !fm.fileExists(atPath: backup.path) { try original.write(to: backup, options: .withoutOverwriting) }
        guard try Data(contentsOf: file) == original else { throw Failure.changed }
        try updated.write(to: file, options: .atomic)
        return true
    }
}
