#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 125hz
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Madeira Dock's client-component setup (SteamRuntime.swift): the production ZIP
reader and Steam discovery-registry writer, compiled on the host with synthetic
archives. Never downloads anything and never runs Steam or Wine.

Also checks the pins: one HTTPS Valve host, well-formed sizes and SHA-256 sums,
and a client DLL hash the pinned Dock host supports (madeira-dock).
Pass real package files as arguments to also unpack them.
"""
from pathlib import Path
import hashlib, io, os, re, shutil, struct, subprocess, sys, tempfile, zipfile
root = Path(__file__).resolve().parents[2]
SWIFTC = os.environ.get('SWIFTC') or shutil.which('swiftc') or str(Path.home() / '.local/share/swiftly/bin/swiftc')
source = root / 'app/Madeira/SteamRuntime.swift'
text = source.read_text()
assert 'static let origin = "https://client-update.akamai.steamstatic.com/"' in text
pins = re.findall(r'Package\(file: "([^"]+)", bytes: ([0-9_]+),\s*sha256: "([0-9a-f]+)"\)', text)
assert len(pins) == 3 and all(len(s) == 64 and int(b.replace('_', '')) > 0 and '/' not in f for f, b, s in pins), pins
client = re.search(r'static let clientSHA256 = "([0-9a-f]{64})"', text).group(1)
layouts = root / 'madeira-dock/src/client_layout.c'
if layouts.exists():
    assert f'"{client}"' in layouts.read_text(), 'the pinned client DLL is not a build the Dock host supports'
    print('PASS: pinned client DLL is a build the pinned Dock host supports')
else:
    print('SKIP: madeira-dock not checked out; client pin cross-check not run')
assert 'url?.host == "client-update.akamai.steamstatic.com"' in text and 'url?.scheme == "https"' in text
print('PASS: three pinned packages from one HTTPS Valve host; redirects stay on it')
with tempfile.TemporaryDirectory(prefix='madeira-runtime-') as tmp:
    tmp = Path(tmp)
    (tmp/'module.modulemap').write_text('module zlib [system] { header "/usr/include/zlib.h" export * link "z" }')
    main = r'''
import Foundation
let fm = FileManager.default
let mode = CommandLine.arguments[1]
if mode == "registry" {
    var image = Data(repeating: 0, count: 128)
    image[0] = 0x4d; image[1] = 0x5a; image[60] = 64
    image[64] = 0x50; image[65] = 0x45
    image[68] = 0x64; image[69] = 0x86
    image[88] = 0x0b; image[89] = 0x02
    assert(SteamRuntimeFiles.isAMD64Image(image))
    var wrong = image; wrong[68] = 0x4c; wrong[69] = 0x01
    assert(!SteamRuntimeFiles.isAMD64Image(wrong))
    wrong = image; wrong[88] = 0x0b; wrong[89] = 0x01
    assert(!SteamRuntimeFiles.isAMD64Image(wrong))
    wrong = image; wrong[60] = 0xff; wrong[61] = 0xff
    assert(!SteamRuntimeFiles.isAMD64Image(wrong))
    wrong = image; wrong[0] = 0
    assert(!SteamRuntimeFiles.isAMD64Image(wrong))
    assert(!SteamRuntimeFiles.isAMD64Image(Data()))
    assert(!SteamRuntimeFiles.isAMD64Image(image.prefix(90).dropFirst()))
    print("PASS: AMD64 PE32+ runtime guard rejects x86, mixed headers, invalid offsets and truncation")
    let update = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: update) }
    let stage = update.appendingPathComponent("stage"), drive = update.appendingPathComponent("drive"), backup = update.appendingPathComponent("backup")
    let installed = drive.appendingPathComponent(SteamRuntimeFiles.relativeRoot)
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    try fm.createDirectory(at: installed, withIntermediateDirectories: true)
    let names = ["SDL3.dll", "steamclient64.dll", "steam.exe"]
    let old = Dictionary(uniqueKeysWithValues: names.map { ($0.lowercased(), "old:" + $0) })
    func put(_ text: String, _ file: URL) throws { try Data(text.utf8).write(to: file) }
    func read(_ file: URL) -> String { try! String(contentsOf: file, encoding: .utf8) }
    let hash: (Data) -> String = { String(decoding: $0, as: UTF8.self) }
    for name in names { try put("new:" + name, stage.appendingPathComponent(name)); try put("old:" + name, installed.appendingPathComponent(name)) }
    let saves = installed.appendingPathComponent("steamapps/common/Fixture")
    try fm.createDirectory(at: saves, withIntermediateDirectories: true)
    try put("save kept", saves.appendingPathComponent("save.bin"))
    try put("account kept", installed.appendingPathComponent("loginusers.vdf"))
    var commits = 0
    try put("unknown", installed.appendingPathComponent("steam.exe"))
    do {
        try SteamRuntimeFiles.publish(stage: stage, drive: drive, backupRoot: backup, names: names, legacy: old, hash: hash, checkQuiescent: {}, beforeCommit: { commits += 1 })
        fatalError("unknown file replaced")
    } catch SteamRuntimeFiles.Failure.conflict { }
    assert(commits == 0 && !fm.fileExists(atPath: backup.path))
    assert(read(installed.appendingPathComponent("SDL3.dll")) == "old:SDL3.dll")
    try put("old:steam.exe", installed.appendingPathComponent("steam.exe"))
    enum Interrupted: Error { case stop }
    var guards = 0
    do {
        try SteamRuntimeFiles.publish(stage: stage, drive: drive, backupRoot: backup, names: names, legacy: old, hash: hash,
            checkQuiescent: { guards += 1; if guards == 4 { throw Interrupted.stop } }, beforeCommit: {
                commits += 1
                for name in names { assert(read(backup.appendingPathComponent(name)) == "old:" + name) }
            })
        fatalError("interruption ignored")
    } catch Interrupted.stop { }
    assert(read(installed.appendingPathComponent("SDL3.dll")) == "new:SDL3.dll")
    assert(read(installed.appendingPathComponent("steam.exe")) == "old:steam.exe")
    try SteamRuntimeFiles.publish(stage: stage, drive: drive, backupRoot: backup, names: names, legacy: old, hash: hash, checkQuiescent: {}, beforeCommit: { commits += 1 })
    for name in names {
        assert(read(installed.appendingPathComponent(name)) == "new:" + name)
        assert(read(backup.appendingPathComponent(name)) == "old:" + name)
    }
    try SteamRuntimeFiles.publish(stage: stage, drive: drive, backupRoot: backup, names: names, legacy: old, hash: hash, checkQuiescent: {}, beforeCommit: {})
    assert(read(saves.appendingPathComponent("save.bin")) == "save kept")
    assert(read(installed.appendingPathComponent("loginusers.vdf")) == "account kept")
    try put("old:SDL3.dll", installed.appendingPathComponent("SDL3.dll"))
    do {
        try SteamRuntimeFiles.publish(stage: stage, drive: drive, backupRoot: backup, names: names, legacy: old, hash: hash, checkQuiescent: {}, beforeCommit: { try put("concurrent edit", installed.appendingPathComponent("SDL3.dll")) })
        fatalError("concurrent edit replaced")
    } catch SteamRuntimeFiles.Failure.conflict { }
    assert(read(installed.appendingPathComponent("SDL3.dll")) == "concurrent edit")
    print("PASS: complete preflight, verified backups, interrupted upgrade/retry, idempotence, unrelated files and concurrent-edit refusal")
    let original = "WINE REGISTRY Version 2\n\n[Software\\\\Keep]\n\"Unrelated\"=\"preserved\"\n"
    for machine in [false, true] {
        let result = try SteamRuntimeFiles.registry(original, machine: machine)
        assert(result.contains("\"Unrelated\"=\"preserved\""))
        let repeated = try SteamRuntimeFiles.registry(result, machine: machine)
        assert(repeated == result)
        if machine { assert(result.contains("Wow6432Node")) }
        else { assert(result.contains("ActiveProcess") && result.contains("SteamExe")) }
    }
    let conflict = "WINE REGISTRY Version 2\n\n[Software\\\\Valve\\\\Steam]\n\"SteamPath\"=\"another location\"\n"
    do { _ = try SteamRuntimeFiles.registry(conflict, machine: false); fatalError("conflict accepted") }
    catch SteamRuntimeFiles.Failure.conflict { }
    do { _ = try SteamRuntimeFiles.registry("invalid", machine: true); fatalError("invalid hive accepted") }
    catch SteamRuntimeFiles.Failure.prefixMissing { }
    for path in ["../escape", "/absolute", "c:/other", "a\\b", "a//b", "a/./b", "a/../b", "a/space "] {
        assert(!SteamRuntimeFiles.validPath(path))
    }
    let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: folder.appendingPathComponent("Bin"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    _ = try SteamRuntimeFiles.destination("Bin/new.dll", under: folder)
    do { _ = try SteamRuntimeFiles.destination("bin/new.dll", under: folder); fatalError("case collision accepted") }
    catch SteamRuntimeFiles.Failure.conflict { }
    try fm.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: folder.appendingPathComponent("Bin"))
    do { _ = try SteamRuntimeFiles.destination("link/new.dll", under: folder); fatalError("symlink accepted") }
    catch SteamRuntimeFiles.Failure.conflict { }
    print("PASS: discovery keys, idempotence, unrelated settings, conflicts and path rules")
} else {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    do {
        var files: [String: Data] = [:]
        try SteamRuntimeFiles.unpack(data) { files[$0] = $1 }
        if mode == "reject" { fatalError("malformed archive accepted") }
        for (name, data) in files where SteamRuntimeFiles.criticalFileSHA256[name] != nil {
            assert(SteamRuntimeFiles.isAMD64Image(data))
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        for (name, data) in files {
            let url = output.appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        print("PASS: extracted \(files.count) files")
    } catch {
        if mode != "reject" { throw error }
        print("PASS: rejected malformed archive")
    }
}
'''
    (tmp/'main.swift').write_text(main)
    exe = tmp/'check'
    subprocess.run([SWIFTC, '-I', str(tmp), str(source), str(tmp/'main.swift'), '-o', str(exe)], check=True)
    subprocess.run([str(exe), 'registry'], check=True)
    def archive(items, compression=zipfile.ZIP_DEFLATED):
        out = io.BytesIO()
        with zipfile.ZipFile(out,'w',compression=compression) as z:
            for name,data in items: z.writestr(name,data)
        return out.getvalue()
    def run(data, reject=False):
        p=tmp/'fixture.zip'; p.write_bytes(data)
        output=tmp/'out'
        subprocess.run([str(exe),'reject' if reject else 'extract',str(p),str(output)],check=True,stdout=subprocess.DEVNULL)
        if not reject:
            with zipfile.ZipFile(p) as z:
                for e in z.infolist():
                    name=e.filename.replace('\\','/')
                    if not name.endswith('/'): assert (output/name).read_bytes()==z.read(e)
    good=archive([('bin/',b''),('bin/library.dll',b'abcdefgh'*4096),('empty',b'')],zipfile.ZIP_STORED)
    run(good)
    good=archive([('library.dll',b'abcdefgh'*4096),('empty',b'')])
    run(good)
    run(archive([('bin\\module.dll',b'windows path')]))
    for path in ['../outside','/outside','c:/outside','a\\..\\b','a/../b']:
        run(archive([(path,b'x')]),True)
    run(archive([('Name',b'x'),('name',b'y')]),True)
    entry=zipfile.ZipInfo('link'); entry.create_system=3; entry.external_attr=(0o120777 << 16)
    run(archive([(entry,b'../outside')]),True)
    run(good[:-10],True)
    bad=bytearray(good); central=bad.index(b'PK\x01\x02'); bad[central+16]^=1; run(bad,True)
    bad=bytearray(good); struct.pack_into('<I',bad,central+24,512*1024*1024); run(bad,True)
    bad=bytearray(good); bad[6]|=1; bad[central+8]|=1; run(bad,True)
    bad=bytearray(good); struct.pack_into('<I',bad,central+42,0xffffffff); run(bad,True)
    print('PASS: stored/deflate/empty content, traversal, duplicates, symlinks, CRC, sizes, flags, offsets and truncation')
    for path in sys.argv[1:]:
        p=Path(path); data=p.read_bytes(); run(data)
        print('PASS: real package SHA-256',hashlib.sha256(data).hexdigest())
