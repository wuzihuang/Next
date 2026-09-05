#!/usr/bin/env python3
"""Exercise production diagnostic readback without changing save semantics."""
from pathlib import Path
import subprocess
import tempfile

app = Path(__file__).resolve().parents[2]
source = (app / 'NextBody/Services/HomeSnapshot.swift').read_text()
start = source.index('    private static func recordReadback(')
end = source.index('\n    #endif', start)
helper = source[start:end].replace('private static func', 'static func', 1)
harness = '''
import Foundation
final class NightDiagnostics {
    static let shared = NightDiagnostics()
    var isEnabled = true
    var events: [[String: String]] = []
    func record(_ event: String, fields: [String: String]) { events.append(fields) }
}
enum Probe {
''' + helper + '''
}
enum ReadFailure: Error { case unavailable }
let expected = Data([1, 2, 3])
let fields = ["day": "2026-09-05"]
Probe.recordReadback(expected: expected, event: "test", fields: fields) { expected }
Probe.recordReadback(expected: expected, event: "test", fields: fields) { nil }
Probe.recordReadback(expected: expected, event: "test", fields: fields) { Data([4]) }
Probe.recordReadback(expected: expected, event: "test", fields: fields) { throw ReadFailure.unavailable }
NightDiagnostics.shared.isEnabled = false
Probe.recordReadback(expected: expected, event: "disabled", fields: fields) { fatalError("disabled diagnostics must not read") }
let events = NightDiagnostics.shared.events
precondition(events.map { $0["status"]! } == ["matched", "missing", "mismatched", "failed"])
precondition(events.allSatisfy { $0["day"] == "2026-09-05" })
precondition(events.last?["errorType"] == "ReadFailure")
precondition(events.last?.count == 3)
print("PASS: actual readback distinguishes matched/missing/mismatched/failure and never propagates diagnostic errors")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'test.swift'
    path.write_text(harness)
    subprocess.run(['swift', str(path)], check=True)
