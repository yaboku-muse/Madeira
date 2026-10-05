#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 125hz
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Run the actual native control transfer against a bounded local HTTP server."""
from pathlib import Path
import http.server
import subprocess
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Madeira/SwiftSteam/Content/DepotDownloader.swift').read_text()
control = source[source.index('struct ContentControlRequest:'):source.index('struct ContentProcessCPUInterval {')]
lock = threading.Lock()
counts = {'active': 0, 'peak': 0, 'success': 0}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        with lock:
            counts['active'] += 1
            counts['peak'] = max(counts['peak'], counts['active'])
        try:
            time.sleep(0.3 if self.path.startswith('/slow') else 0.03)
            payload = b'x' * 16384
            self.send_response(503 if self.path.startswith('/failed') else 200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            if self.path.startswith('/ok'):
                with lock:
                    counts['success'] += 1
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with lock:
                counts['active'] -= 1

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
fixture = r'''
import Foundation
enum SteamError: Error { case chunkDownloadFailed(String) }
@main struct Probe {
    static func main() async throws {
        let base = CommandLine.arguments[1]
        func request(_ path: String, _ bytes: UInt64 = 16384) -> ContentControlRequest {
            ContentControlRequest(url: URL(string: base + path + "?auth=PRIVATE_FIXTURE")!, bytes: bytes)
        }
        let requests = (0..<24).map { request("/ok/\($0)") }
        let results = try await ContentControl.run(requests)
        precondition(results.count == 3)
        precondition(results.allSatisfy { $0.bytes == 24 * 16384 && $0.seconds > 0.03 && $0.seconds.isFinite })
        let encoded = try JSONEncoder().encode(results)
        let decoded = try JSONDecoder().decode([ContentControlTrial].self, from: encoded)
        precondition(decoded.map(\.bytes) == results.map(\.bytes))
        precondition(!String(decoding: encoded, as: UTF8.self).contains("PRIVATE_FIXTURE"))
        for invalid in [[], [request("/ok", 0)], [request("/ok", 8 * 1024 * 1024 + 1)],
                        Array(repeating: request("/ok"), count: 257),
                        [request("/ok"), ContentControlRequest(url: URL(string: "http://other.invalid/ok")!, bytes: 1)],
                        Array(repeating: request("/ok", 8 * 1024 * 1024), count: 9)] {
            do { _ = try await ContentControl.run(invalid); fatalError("invalid sample accepted") }
            catch SteamError.chunkDownloadFailed { }
        }
        for invalid in [[request("/failed")], [request("/wrong-size", 1)]] {
            do { _ = try await ContentControl.run(invalid); fatalError("bad response accepted") }
            catch SteamError.chunkDownloadFailed { }
        }
        let cancelled = Task { try await ContentControl.run([request("/slow")]) }
        try await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancelled control returned trials") }
        catch { }
        print("PASS: actual native URLSession control, three bounded trials, byte/HTTP refusal, cancellation and numeric JSON")
    }
}
'''
try:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)
        # Keep declarations before @main; compile the production transfer code.
        fixture = fixture.replace('@main struct Probe', control + '\n@main struct Probe')
        (path / 'probe.swift').write_text(fixture)
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'probe.swift'), '-o', str(path / 'probe')], check=True, timeout=120)
        result = subprocess.run([str(path / 'probe'), f'http://127.0.0.1:{server.server_port}'], capture_output=True, text=True, check=True, timeout=30)
        assert counts['success'] == 72, counts
        assert 1 < counts['peak'] <= 8, counts
        assert 'PRIVATE_FIXTURE' not in result.stdout + result.stderr
        print(result.stdout, end='')
        print(f"PASS: server observed 72 successful sample requests and peak concurrency {counts['peak']}")
finally:
    server.shutdown()
    server.server_close()
