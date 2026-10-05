#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Exercise production URLSession metrics with delayed localhost responses on macOS."""
import http.server
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

if sys.platform != 'darwin':
    raise SystemExit('This check requires Apple URLSession metrics; run the macOS host job.')

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Madeira/SwiftSteam/Content/DepotDownloader.swift').read_text()
collector = source.split('final class ContentNetworkMetrics:', 1)[1].split('\nfinal class ContentHostHealth:', 1)[0]
collector = 'final class ContentNetworkMetrics:' + collector
http_source = source.split('    private nonisolated static let http:', 1)[1].split('    /// Replaces the content server', 1)[0]
http_source = '    private nonisolated static let http:' + http_source
download = source.split('    private nonisolated static func download(', 1)[1].split('    // MARK: - Manifest', 1)[0]
download = '    private nonisolated static func download(' + download

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        time.sleep(0.08)
        payload = b'fixture response'
        self.send_response(503 if self.path.startswith('/failed') else 200)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory)
        swift = 'import Foundation\nenum SteamError: Error { case chunkDownloadFailed(String) }\n'
        swift += collector + '\nenum Probe {\n' + http_source + download
        swift += 'static func get(_ url: String, _ metrics: ContentNetworkMetrics) async throws -> Data { try await download(url, metrics: metrics) }\n}\n'
        swift += '''
@main struct Main {
    static func main() async throws {
        let metrics = ContentNetworkMetrics()
        let base = CommandLine.arguments[1]
        for _ in 0..<2 {
            let data = try await Probe.get(base + "/ok?auth=SECRET_FIXTURE_TOKEN", metrics)
            guard data == Data("fixture response".utf8) else { fatalError("payload changed") }
        }
        do {
            _ = try await Probe.get(base + "/failed?auth=SECRET_FIXTURE_TOKEN", metrics)
            fatalError("HTTP error accepted")
        } catch SteamError.chunkDownloadFailed { }
        for line in metrics.report(depotID: 123) { print(line) }
    }
}
'''
        path.joinpath('probe.swift').write_text(swift)
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'probe.swift'), '-o', str(path / 'probe')], check=True, timeout=120)
        result = subprocess.run([str(path / 'probe'), f'http://127.0.0.1:{server.server_port}'], text=True, capture_output=True, check=True, timeout=30)
        log = result.stdout
        assert 'requests=3 completed=3 metrics-callbacks=3 active-requests=0' in log, log
        assert 'transactions=3' in log and 'statuses=200:2,503:1' in log, log
        assert 'tls=unavailable' in log, log
        timing = re.search(r'ttfb=([0-9.]+)s/3', log)
        assert timing and float(timing[1]) >= 0.15, log
        assert 'SECRET_FIXTURE_TOKEN' not in log and '?auth=' not in log, log
        print(log, end='')
        print('check-depot-network-metrics: delayed success/error transactions, lifecycle and secret-free timing passed')
finally:
    server.shutdown()
    server.server_close()
