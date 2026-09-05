"""Exercise the actual shared HRV presentation selector, including explicit-empty archives."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
s = (root / 'NextBody/Features/Vitals/VitalsReadout.swift').read_text()
selector = s[s.index('    static func sleepHRVSamples('):s.index('    private static func sleep(m:')]
stubs = """
import Foundation
struct VitalSample { let ts: Date; let hr: Int?; let stress: Int?; var hrv: Double? = nil }
struct SleepHRVPoint { let ts: Date; let rmssdMS: Double }
struct SleepSummary {
 var hrv: [SleepHRVPoint]?
 var validWindow = true
 func containsSleepTimestamp(_ ts: Date) -> Bool { validWindow && (0..<3600).contains(ts.timeIntervalSince1970) }
}
"""
harness = r"""
let ts = Date(timeIntervalSince1970: 60)
let fallback = [VitalSample(ts: ts, hr: nil, stress: nil, hrv: 10)]
let old = VitalsReadout.sleepHRVSamples(night: SleepSummary(hrv: nil), fallback: fallback)
let empty = VitalsReadout.sleepHRVSamples(night: SleepSummary(hrv: []), fallback: fallback)
let fresh = VitalsReadout.sleepHRVSamples(night: SleepSummary(hrv: [SleepHRVPoint(ts: ts, rmssdMS: 42), SleepHRVPoint(ts: ts.addingTimeInterval(7200), rmssdMS: 88)]), fallback: fallback)
let missing = VitalsReadout.sleepHRVSamples(night: SleepSummary(hrv: nil, validWindow: false), fallback: fallback)
let passed = old.first?.hrv == 10 && empty.isEmpty && fresh.count == 1 && fresh.first?.hrv == 42 && missing.isEmpty
print("\(passed ? "PASS" : "FAIL"): archived HRV wins; explicit empty stays empty; legacy falls back only within sleep")
exit(passed ? 0 : 1)
"""
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(stubs + 'enum VitalsReadout {\n' + selector + '}\n' + harness)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test')]).returncode)
