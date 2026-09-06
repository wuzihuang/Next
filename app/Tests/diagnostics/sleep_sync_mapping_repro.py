"""Compile the sync's actual pure helpers; assert full-night pages and independent sensors."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'NextBody/Services/Band/OriginDataSync.swift').read_text()

def function(name):
    start = source.index('    static func ' + name + '(')
    opening = source.index('{', start)
    depth = 1
    position = opening + 1
    while depth:
        depth += (source[position] == '{') - (source[position] == '}')
        position += 1
    return source[start:position]

main = '''
import Foundation
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func date(_ value: String) -> Date { HealthSampleMapping.sleepInstant(value, calendar: calendar)! }
let start = date("2026-09-04 23:00")
let wake = date("2026-09-05 13:09")
let now = date("2026-09-05 14:00")
let smallHours = date("2026-09-06 02:00")
let today = UserDay.containing(smallHours, calendar: calendar)
let yesterday = UserDay(date: calendar.date(byAdding: .day, value: -1, to: today.start)!)
precondition(Replay.pages(for: yesterday, now: smallHours, calendar: calendar) == [2, 1],
             "closing the previous user day before 04:00 must use natural-calendar pages")
precondition(Replay.pages(for: today, now: smallHours, calendar: calendar) == [1, 0])
precondition(Replay.pages(for: today, now: date("2026-09-05 12:00"), calendar: calendar) == [0])
let offsets = Replay.nightPageOffsets(start: start, wake: wake, now: now, calendar: calendar)
precondition(offsets == [1, 0], "full sleep must read both device calendar pages")
precondition(Replay.nightPageOffsets(start: wake, wake: start, now: now, calendar: calendar).isEmpty)
precondition(Replay.nightPageOffsets(start: start, wake: wake, now: start, calendar: calendar).isEmpty)
let standalone = Replay.auxiliarySamples(temperatureTicks: [start: 33.7], hrvTicks: [wake: 42])
precondition(standalone.count == 2, "auxiliary SDK ticks must survive without origin ticks")
precondition(standalone.first?.temp == 33.7 && standalone.last?.hrv == 42)
let combined = Replay.auxiliarySamples(temperatureTicks: [start: 33.7], hrvTicks: [start: 42])
precondition(combined.count == 1 && combined[0].temp == 33.7 && combined[0].hrv == 42)
print("PASS: actual sync user-day pages before 04:00, full-night pages, and independent temperature/HRV ticks")
'''
with tempfile.TemporaryDirectory() as directory:
    target = Path(directory)
    (target / 'helpers.swift').write_text('import Foundation\nenum Replay {\n' + function('pages') + '\n' + function('nightPageOffsets') + '\n' + function('auxiliarySamples') + '\n}')
    (target / 'main.swift').write_text(main)
    subprocess.run(['swiftc', str(root / 'NextBody/Services/Band/HealthSampleMapping.swift'), str(root / 'NextBody/Services/Band/VitalSample.swift'), str(root / 'NextBody/Services/Band/UserDay.swift'), str(root / 'NextBody/Services/Band/VitalsTimelinePolicy.swift'), str(target / 'helpers.swift'), str(target / 'main.swift'), '-o', str(target / 'replay')], check=True)
    result = subprocess.run([str(target / 'replay')], capture_output=True, text=True)
    print(result.stdout if result.returncode == 0 else 'FAIL: actual sync helpers dropped cross-day sleep or standalone health ticks')
    raise SystemExit(result.returncode)
