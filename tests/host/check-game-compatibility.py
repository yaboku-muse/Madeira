#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Compile the production renderer adapter and exercise real file preservation."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
production = (root / 'app/Madeira/GameCompatibility.swift').read_text(encoding='utf-8')
fixture = r'''
func check(_ condition: @autoclosure () -> Bool) { precondition(condition()) }
func rejects(_ text: String, line: UInt = #line) {
    do { _ = try TeardownRendererSettings.selectingD3D12(Data(text.utf8)); preconditionFailure("accepted invalid XML fixture line \(line)") }
    catch { }
}
let source = """
<?xml version="1.0" encoding="UTF-8"?>
<registry version="2.1.0">
  <options><gfx><gfxapi value="0"/><d3d12support value='0'/><quality value="3"/></gfx>
  <audio><musicvolume value="93"/></audio><input><label value="船 &amp; é"/></input></options>
</registry>
""".replacingOccurrences(of: "\n", with: "\r\n")
let selected = source.replacingOccurrences(of: "gfxapi value=\"0\"", with: "gfxapi value=\"1\"")
    .replacingOccurrences(of: "d3d12support value='0'", with: "d3d12support value='1'")
let original = Data(source.utf8)
check(try! TeardownRendererSettings.selectingD3D12(original) == Data(selected.utf8))
check(try! TeardownRendererSettings.selectingD3D12(Data(selected.utf8)) == Data(selected.utf8))
check(GameCompatibilityProfile.resolve(appID: 3527290) == nil)
check(GameCompatibilityProfile.resolve(appID: 1167630, enabled: false) == nil)
let policy = GameCompatibilityProfile.resolve(appID: 1167630)!
check(policy.preferredRenderer == .d3d12 && policy.revision == 1)
rejects(source.replacingOccurrences(of: "2.1.0", with: "99.0"))
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: ""))
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: "<gfxapi value=\"0\"/><gfxapi value=\"1\"/>"))
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: "<gfxapi value=\"2\"/>"))
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: "<gfxapi value=\"0\" evil=\"yes\"/>"))
rejects(source.replacingOccurrences(of: "</options>", with: "<other><gfxapi value=\"0\"/></other></options>"))
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: "<!-- <gfxapi value=\"0\"/> --><gfxapi value=\"0\"></gfxapi>"))
rejects(source + "<!-- <gfxapi value=\"0\"/> -->")
rejects(source.replacingOccurrences(of: "<gfxapi value=\"0\"/>", with: "<?hint <gfxapi value=\"0\"/> ?><gfxapi value=\"0\"></gfxapi>"))
rejects("<!DOCTYPE registry [<!ENTITY x SYSTEM 'file:///private/file'>]>" + source)
rejects(source.replacingOccurrences(of: "<quality value=\"3\"/>", with: "<![CDATA[<gfxapi value=\"0\"/>]]>"))
rejects(source.replacingOccurrences(of: "</registry>", with: ""))
rejects(String(repeating: "x", count: 1_048_577))
let fm = FileManager.default
let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
try fm.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: directory) }
let file = directory.appendingPathComponent("options.xml")
check(try! policy.prepare(options: file) == false && !fm.fileExists(atPath: file.path))
try original.write(to: file)
check(try! policy.prepare(options: file))
let backup = directory.appendingPathComponent("options.xml.madeira-renderer-backup")
check(try! Data(contentsOf: backup) == original)
check(try! Data(contentsOf: file) == Data(selected.utf8))
check(try! policy.prepare(options: file) == false)
try original.write(to: file)
check(try! policy.prepare(options: file))
check(try! Data(contentsOf: backup) == original)
let unsupported = Data(source.replacingOccurrences(of: "2.1.0", with: "3.0").utf8)
try unsupported.write(to: file)
do { _ = try policy.prepare(options: file); preconditionFailure() } catch { }
check(try! Data(contentsOf: file) == unsupported)
try fm.removeItem(at: file)
let target = directory.appendingPathComponent("other.xml")
try original.write(to: target)
try fm.createSymbolicLink(at: file, withDestinationURL: target)
do { _ = try policy.prepare(options: file); preconditionFailure() } catch { }
check(try! Data(contentsOf: target) == original)
print("PASS: actual profile adapter; exact two-value edits; Unicode/CRLF/unknown-setting preservation; backups; repeat launches; unknown/malformed XML; symlink refusal; generic and disabled profiles")
'''
content = (root / 'app/Madeira/ContentView.swift').read_text(encoding='utf-8')
start = content[content.index('private func startDock('):]
assert start.index('cloudClear(') < start.index('compatibility.prepare(options:') < start.index('runWineFullSequence(profile:')
assert start.index('wine_process_is_running() == 0', start.index('await SteamOwnedLibrary.shared.prepareDock()')) < start.index('compatibility.prepare(options:')
assert 'enabled: profile?.automaticCompatibility != false' in start
project = (root / 'app/Madeira.xcodeproj/project.pbxproj').read_text()
assert project.count('A1F0FF01 /* GameCompatibility.swift in Sources */') == 2
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(production + '\n' + fixture, encoding='utf-8')
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
