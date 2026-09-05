"""Replay the actual sleep chart window: missing bounds must never admit daytime HRV."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
charts = (root / 'NextBody/Features/Vitals/VitalsDetailCharts.swift').read_text()
window = charts[charts.index('struct VitalsWindow {'):charts.index('/// The 24-hour trace:')]
policy = (root / 'NextBody/Services/Band/VitalsTimelinePolicy.swift').read_text()
models = (root / 'NextBody/Models/Metrics.swift').read_text()
summary = models[models.index('struct SleepInterval:'):models.index('/// One respiratory reading')]
summary += "struct SleepStageRun: Codable, Hashable { var stage: Int; var minutes: Int }\nstruct SleepRespirationPoint: Codable, Hashable {}\nstruct OvernightOxygenPoint: Codable, Hashable {}\n"
harness = '''
struct UserDay { let start: Date; let end: Date }
enum Fmt { static func clock(_ date: Date) -> String { "clock" } }
func L(_ key: String) -> String { key }
let start = Date(timeIntervalSince1970: 100000)
let day = UserDay(start: start, end: start.addingTimeInterval(86400))
let missing = VitalsWindow.night(start: nil, end: nil, fallback: day)
let valid = VitalsWindow.night(start: start, end: start.addingTimeInterval(13 * 3600), fallback: day)
let splitNight = SleepSummary(totalMinutes: 120, deepMinutes: 40, lightMinutes: 80, wakeCount: 1,
    sleepStart: start, wakeAt: start.addingTimeInterval(4 * 3600),
    intervals: [SleepInterval(start: start, end: start.addingTimeInterval(3600)),
                SleepInterval(start: start.addingTimeInterval(3 * 3600), end: start.addingTimeInterval(4 * 3600))])
let segmentPassed = splitNight.containsSleepTimestamp(start.addingTimeInterval(1800))
    && !splitNight.containsSleepTimestamp(start.addingTimeInterval(2 * 3600))
    && splitNight.containsSleepTimestamp(start.addingTimeInterval(3.5 * 3600))
    && !splitNight.containsSleepTimestamp(start.addingTimeInterval(4 * 3600))
print("\\(segmentPassed ? "PASS" : "FAIL"): split sleep includes both sessions, excludes awake gap and wake endpoint")
let passed = segmentPassed && !missing.contains(start.addingTimeInterval(12 * 3600)) && missing.labels.isEmpty && valid.contains(start.addingTimeInterval(12.5 * 3600)) && !valid.labels.isEmpty
print("\\(passed ? "PASS" : "FAIL"): missing sleep window hides daytime HRV and clock; late wake preserves data")
exit(passed ? 0 : 1)
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(policy + window + summary + harness)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test')]).returncode)
