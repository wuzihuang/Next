"""Compile the actual minute HRV model and repository parser; no user records or network."""
from pathlib import Path
import subprocess
import tempfile

app = Path(__file__).resolve().parents[2]


def extract(path, marker):
    source = path.read_text()
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


repository = app / 'NextBody/Services/Repository.swift'
source = 'import Foundation\n' + extract(app / 'NextBody/Models/Metrics.swift', 'struct SleepHRVPoint:')
source += '\nenum Repository {\n'
for marker in ['static func sleepHRV(', 'static func sleepHRVInvalidations(',
               'private static func numberStatic(', 'static func timestamp(']:
    source += extract(repository, marker) + '\n'
source += r'''
}
let start = Date(timeIntervalSince1970: 1_700_000_000)
let wake = start.addingTimeInterval(8 * 3600)
let minute = start.addingTimeInterval(60)
let firstRead = wake.addingTimeInterval(300)
let correction = firstRead.addingTimeInterval(300)
let laterRead = correction.addingTimeInterval(300)
let iso = ISO8601DateFormatter()
func point(_ value: Double, _ clock: Date?) -> [String: Any] {
    var row: [String: Any] = ["ts": iso.string(from: minute), "rmssd_ms": value]
    if let clock { row["observed_at"] = iso.string(from: clock) }
    return row
}
func invalidation(_ at: Date = minute, _ clock: Date = correction) -> [String: Any] {
    ["ts": iso.string(from: at), "observed_at": iso.string(from: clock),
     "reason": "insufficient_adjacent_rr"]
}
let raw: [String: Any] = ["hrv": [point(200, firstRead)],
    "hrv_invalidated": [invalidation(), invalidation(minute, firstRead)]]
let invalidations = Repository.sleepHRVInvalidations(raw: raw, start: start, wake: wake)
precondition(invalidations[minute] == correction)
precondition(Repository.sleepHRV(raw: raw, start: start, wake: wake)?.isEmpty == true)
for oldClock in [nil, firstRead, correction] as [Date?] {
    let legacy: [String: Any] = ["hrv": [point(200, oldClock)], "hrv_invalidated": [invalidation()]]
    precondition(Repository.sleepHRV(raw: legacy, start: start, wake: wake)?.isEmpty == true,
                 "older, legacy, or simultaneous valid points cannot undo a revocation")
}
let recoveredRaw: [String: Any] = ["hrv": [point(45, laterRead)], "hrv_invalidated": [invalidation()]]
let recovered = Repository.sleepHRV(raw: recoveredRaw, start: start, wake: wake)!
precondition(recovered.first?.rmssdMS == 45 && recovered.first?.observedAt == laterRead)
let stale = [SleepHRVPoint(ts: minute, rmssdMS: 200, observedAt: firstRead)]
precondition(SleepHRVPoint.merging(recovered, with: stale, invalidatedMinutes: invalidations) == recovered)
precondition(SleepHRVPoint.merging(stale, with: recovered, invalidatedMinutes: invalidations) == recovered)
let sameClockConflict = [SleepHRVPoint(ts: minute, rmssdMS: 200, observedAt: laterRead)]
precondition(SleepHRVPoint.merging(recovered, with: sameClockConflict, invalidatedMinutes: invalidations) == recovered,
             "conflicting values with an equal explicit clock keep the stored value")
precondition(SleepHRVPoint.merging(sameClockConflict, with: recovered, invalidatedMinutes: invalidations) == sameClockConflict)
precondition(SleepHRVPoint.merging(recovered, with: recovered, invalidatedMinutes: invalidations) == recovered)
let clockless = [SleepHRVPoint(ts: minute, rmssdMS: 45)]
let newClockless = [SleepHRVPoint(ts: minute, rmssdMS: 50)]
precondition(SleepHRVPoint.merging(clockless, with: newClockless, invalidatedMinutes: [:]) == newClockless)
let bytes = try JSONEncoder().encode(recovered)
let restored = try JSONDecoder().decode([SleepHRVPoint].self, from: bytes)
precondition(restored == recovered)
let oldCache = try JSONDecoder().decode(SleepHRVPoint.self, from: Data("{\"ts\":0,\"rmssdMS\":45}".utf8))
precondition(oldCache.observedAt == nil)
precondition(Repository.sleepHRV(raw: [:], start: start, wake: wake) == nil)
precondition(Repository.sleepHRV(raw: ["hrv": []], start: start, wake: wake)?.isEmpty == true)
let malformed: [String: Any] = ["hrv": [point(301, nil), point(.nan, nil)],
    "hrv_invalidated": [invalidation(wake), invalidation(minute, minute.addingTimeInterval(-60)),
                         invalidation(minute, Date().addingTimeInterval(3_600))]]
precondition(Repository.sleepHRV(raw: malformed, start: start, wake: wake)?.isEmpty == true)
precondition(Repository.sleepHRVInvalidations(raw: malformed, start: start, wake: wake).isEmpty)
print("PASS: minute HRV parser, correction clocks, stale snapshot rejection, later recovery, and legacy cache decoding")
'''
with tempfile.TemporaryDirectory(prefix='next-sleep-hrv-evidence-') as directory:
    root = Path(directory)
    (root / 'main.swift').write_text(source)
    subprocess.run(['swiftc', str(root / 'main.swift'), '-o', str(root / 'check')], check=True)
    raise SystemExit(subprocess.run([str(root / 'check')]).returncode)
