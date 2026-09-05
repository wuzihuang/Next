#!/usr/bin/env python3
"""Compile the actual local overnight writer; verify evidence survives restarts."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'NextBody/Services/NightDiagnostics.swift'
HARNESS = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let start = Date(timeIntervalSince1970: 1_788_566_400)
func writer(_ time: Date, limit: Int = 4096, lease: TimeInterval = 172800) -> NightDiagnostics {
    NightDiagnostics(directory: root, enabled: true, now: { time }, maximumFileBytes: limit, leaseDuration: lease)
}
func records() throws -> [[String: Any]] {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jsonl" }.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            }
        }
}
let a = writer(start)
a.record("escaped", fields: ["value": "quote\" newline\n中文"])
let b = writer(start.addingTimeInterval(60))
b.record("restarted")
let initial = try records()
precondition(initial.count == 2)
precondition((initial[0]["fields"] as! [String: String])["value"] == "quote\" newline\n中文")
precondition(initial[0]["session"] as! String != initial[1]["session"] as! String)
precondition(initial[0]["timezone"] != nil && initial[0]["utcOffsetSeconds"] != nil)
DispatchQueue.concurrentPerform(iterations: 400) { index in b.record("concurrent", fields: ["index": String(index)]) }
let concurrent = try records()
let seq = concurrent.filter { $0["event"] as? String == "concurrent" }.map { $0["sequence"] as! Int }
precondition(seq.count > 0 && Set(seq).count == seq.count && seq == seq.sorted())
for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "jsonl" {
    let bytes = try Data(contentsOf: url)
    precondition(bytes.count <= 4096)
}
let expired = writer(start.addingTimeInterval(172801))
precondition(!expired.isEnabled)
let count = try records().count
expired.record("must_not_write")
let afterExpired = try records().count
precondition(afterExpired == count)
let restartedExpired = writer(start.addingTimeInterval(172802))
precondition(!restartedExpired.isEnabled)
let rotationRoot = root.appendingPathComponent("rotation")
for day in 0..<5 {
    let c = NightDiagnostics(directory: rotationRoot, enabled: true, now: { start.addingTimeInterval(Double(day) * 86400) }, maximumFileBytes: 4096, leaseDuration: 10 * 86400)
    c.record("day")
}
let files = try FileManager.default.contentsOfDirectory(at: rotationRoot, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
precondition(files.count == 3)
let oversizedRoot = root.appendingPathComponent("oversized")
let oversized = NightDiagnostics(directory: oversizedRoot, enabled: true, now: { start })
oversized.record("oversized", fields: ["payload": String(repeating: "x", count: 8193)])
precondition(oversized.status["lastFailure"] == "oversized_fields:0")
let badRoot = root.appendingPathComponent("bad-lease")
try FileManager.default.createDirectory(at: badRoot, withIntermediateDirectories: true)
try Data("invalid".utf8).write(to: badRoot.appendingPathComponent("lease.json"))
let bad = NightDiagnostics(directory: badRoot, enabled: true)
precondition(!bad.isEnabled && bad.status["lastFailure"] != "none")
let disabledRoot = root.appendingPathComponent("disabled")
let disabled = NightDiagnostics(directory: disabledRoot, enabled: false)
disabled.record("disabled")
precondition(!FileManager.default.fileExists(atPath: disabledRoot.path))
print("PASS: restart, escaping, concurrent writes, size bounds, 3-day retention, persistent expiry, corrupt lease fails closed, oversized input rejected, disabled no-op")
'''
with tempfile.TemporaryDirectory(prefix='night-diagnostics-test-') as temp:
    temp = Path(temp)
    (temp / 'main.swift').write_text(HARNESS)
    subprocess.run(['swiftc', '-D', 'DEBUG', str(SOURCE), str(temp / 'main.swift'), '-o', str(temp / 'probe')], check=True)
    subprocess.run([str(temp / 'probe'), str(temp / 'evidence')], check=True)

    (temp / 'main.swift').write_text('import Foundation\nprecondition(!NightDiagnostics.shared.isEnabled)\nprint("PASS: release shared writer disabled")\n')
    subprocess.run(['swiftc', str(SOURCE), str(temp / 'main.swift'), '-o', str(temp / 'release-probe')], check=True)
    subprocess.run([str(temp / 'release-probe')], check=True)
