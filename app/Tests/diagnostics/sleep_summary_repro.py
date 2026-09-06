"""Run OriginDataSync's actual summary merge with minimal value-model test doubles."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'NextBody/Services/Band/OriginDataSync.swift').read_text()
start = source.index('    private static func sleepSummary(')
opening = source.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
helper = source[start:end].replace('private static func', 'static func', 1)
for name in ['sleepOnCalendarDay', 'clearWrongDaySleep', 'nightWindow']:
    begin = source.index('    private static func ' + name + '(')
    opening = source.index('{', begin)
    depth, finish = 1, opening + 1
    while depth:
        depth += (source[finish] == '{') - (source[finish] == '}')
        finish += 1
    helper += '\n' + source[begin:finish].replace('private static func', 'static func', 1)
models = '''
import Foundation
struct UserDay: Equatable {
    let key: String
    var start: Date { ISO8601DateFormatter().date(from: key + "T04:00:00Z")! }
}
struct SleepStageRun { let stage: Int; let minutes: Int }
struct SleepInterval { let start: Date; let end: Date }
struct OvernightOxygenPoint { let ts: Date; let percent: Int }
struct SleepRespirationPoint { let ts: Date; let breathsPerMinute: Double }
struct SleepSummary {
    let totalMinutes: Int; let deepMinutes: Int; let lightMinutes: Int; let wakeCount: Int
    var line: [SleepStageRun]; var sleepStart: Date?; var wakeAt: Date?
    var spo2: [OvernightOxygenPoint] = []
    var respiration: [SleepRespirationPoint]? = nil
    var hrv: [SleepHRVPoint]? = nil
    var hrvInvalidatedMinutes: [Date: Date]? = nil
    var intervals: [SleepInterval]? = nil
}
struct SleepNight {
    let totalMinutes: Int; let deepMinutes: Int; let lightMinutes: Int; let wakeCount: Int
    var line: [SleepStageRun]; var sleepStart: Date?; var wakeAt: Date?
    var intervals: [SleepInterval]? = nil
}
struct DailyMetrics { let day: UserDay; var sleep: SleepSummary?; var sampleCount: Int = 7 }
final class DataStore {
    var today: DailyMetrics; var history: [DailyMetrics]
    init(today: DailyMetrics, history: [DailyMetrics]) { self.today = today; self.history = history }
}
'''
metrics = (root / 'NextBody/Models/Metrics.swift').read_text()
point_start = metrics.index('struct SleepHRVPoint:')
point_end = metrics.index('{', point_start) + 1
point_depth = 1
while point_depth:
    point_depth += (metrics[point_end] == '{') - (metrics[point_end] == '}')
    point_end += 1
models += metrics[point_start:point_end] + '\n'
main = r'''
import Foundation
NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
let day = UserDay(key: "2026-09-05")
let start = ISO8601DateFormatter().date(from: "2026-09-05T03:00:00Z")!
let wake = start.addingTimeInterval(6 * 3600)
let intervals = [SleepInterval(start: start, end: start.addingTimeInterval(2 * 3600)),
                 SleepInterval(start: start.addingTimeInterval(4 * 3600), end: wake)]
let night = SleepNight(totalMinutes: 240, deepMinutes: 30, lightMinutes: 210, wakeCount: 1,
    line: [], sleepStart: start, wakeAt: wake, intervals: intervals)
let early = start.addingTimeInterval(60)
let gap = start.addingTimeInterval(3 * 3600)
let late = start.addingTimeInterval(5 * 3600)
var old = SleepSummary(totalMinutes: 240, deepMinutes: 30, lightMinutes: 210, wakeCount: 1,
    line: [], sleepStart: start, wakeAt: wake)
old.intervals = intervals
old.respiration = [SleepRespirationPoint(ts: early, breathsPerMinute: 17)]
old.spo2 = [OvernightOxygenPoint(ts: early, percent: 97)]
let store = DataStore(today: DailyMetrics(day: day, sleep: old), history: [])
let result = Replay.sleepSummary(night: night, day: day, store: store,
    oxygen: [gap: 99, late: 96], respiration: [gap: 99, late: 18])!
precondition(result.totalMinutes == 240)
precondition(result.respiration?.map(\.breathsPerMinute) == [17, 18], "preserve old points, reject awake gap")
precondition(result.spo2.map(\.percent) == [97, 96], "oxygen must follow same sleep intervals")
let minuteHRV = Replay.sleepSummary(night: night, day: day, store: store,
    oxygen: [:], respiration: [:], hrv: [start: 42, gap: 99, wake.addingTimeInterval(-60): 53, wake: 88], observedAt: wake)!
precondition(minuteHRV.hrv?.count == 2 && minuteHRV.hrv?.first?.ts == start
             && minuteHRV.hrv?.last?.ts == wake.addingTimeInterval(-60),
             "exact-minute HRV retains boundary minutes and excludes gap/wake")
let repeatedStore = DataStore(today: DailyMetrics(day: day, sleep: minuteHRV), history: [])
let repeated = Replay.sleepSummary(night: night, day: day, store: repeatedStore,
    oxygen: [:], respiration: [:], hrv: [start: 42], observedAt: wake)!
precondition(repeated.hrv?.count == 2, "repeat sync must not duplicate or reweight minute HRV")
let revoked = Replay.sleepSummary(night: night, day: day, store: repeatedStore,
    oxygen: [:], respiration: [:], hrv: [:], invalidHrvMinutes: [start], observedAt: wake.addingTimeInterval(300))!
precondition(revoked.hrv?.count == 1 && revoked.hrv?.first?.ts == wake.addingTimeInterval(-60),
             "explicitly disproved RR minute must be removed while unrelated historical minutes survive")
let revokedStore = DataStore(today: DailyMetrics(day: day, sleep: revoked), history: [])
let staleRead = Replay.sleepSummary(night: night, day: day, store: revokedStore,
    oxygen: [:], respiration: [:], hrv: [start: 200], observedAt: wake)!
precondition(staleRead.hrv?.contains(where: { $0.ts == start }) == false,
             "a stale read must not revive an invalidated minute")
let repairedRead = Replay.sleepSummary(night: night, day: day, store: revokedStore,
    oxygen: [:], respiration: [:], hrv: [start: 45], observedAt: wake.addingTimeInterval(600))!
precondition(repairedRead.hrv?.first?.rmssdMS == 45,
             "a truly later valid observation can restore that minute")
let unknown = Replay.sleepSummary(night: night, day: day,
    store: DataStore(today: DailyMetrics(day: day, sleep: nil), history: []),
    oxygen: [:], respiration: [:], hrv: [:])!
precondition(unknown.hrv == nil, "failed or unknown HRV read must not assert a complete empty night")
let partial = Replay.sleepSummary(night: night, day: day,
    store: DataStore(today: DailyMetrics(day: day, sleep: nil), history: []),
    oxygen: [:], respiration: [:], hrv: [start: 42])!
precondition(partial.hrv?.count == 1, "partial successful pages preserve their actual minute data")
let missing = Replay.sleepSummary(night: night, day: day,
    store: DataStore(today: DailyMetrics(day: day, sleep: nil), history: []),
    oxygen: [:], respiration: [:], hrv: [:], hrvReadComplete: true)!
precondition(missing.hrv?.isEmpty == true, "empty RR produces no invented night HRV")
let historical = DataStore(today: DailyMetrics(day: UserDay(key: "2026-09-06"), sleep: nil),
    history: [DailyMetrics(day: day, sleep: old)])
let historyResult = Replay.sleepSummary(night: nil, day: day, store: historical,
    oxygen: [:], respiration: [:])!
precondition(historyResult.respiration?.count == 1, "empty repeat must retain historical measurement")
let shortNight = SleepNight(totalMinutes: 60, deepMinutes: 10, lightMinutes: 50, wakeCount: 0,
    line: [], sleepStart: late, wakeAt: wake, intervals: nil)
let keptFull = Replay.sleepSummary(night: shortNight, day: day, store: store,
    oxygen: [:], respiration: [late: 19])!
precondition(keptFull.totalMinutes == 240 && keptFull.sleepStart == start,
             "late partial SDK record must not shrink complete local sleep")
let changedWindow = SleepNight(totalMinutes: 300, deepMinutes: 30, lightMinutes: 270, wakeCount: 1,
    line: [], sleepStart: start.addingTimeInterval(-3600), wakeAt: wake, intervals: nil)
let widened = Replay.sleepSummary(night: changedWindow, day: day, store: store,
    oxygen: [:], respiration: [start.addingTimeInterval(-60): 16])!
precondition(widened.intervals == nil, "old intervals must not constrain newly widened window")
precondition(widened.respiration?.first?.breathsPerMinute == 16)
var wrongDay = old
wrongDay.sleepStart = start.addingTimeInterval(86400)
wrongDay.wakeAt = wake.addingTimeInterval(86400)
let badStore = DataStore(today: DailyMetrics(day: day, sleep: wrongDay),
    history: [DailyMetrics(day: day, sleep: wrongDay)])
precondition(Replay.sleepSummary(night: nil, day: day, store: badStore, oxygen: [:], respiration: [:]) == nil,
             "existing sleep filed on the wrong wake day must be ignored")
precondition(Replay.nightWindow(day: day, night: nil, store: badStore) == nil,
             "wrong-day cached sleep must not drive health reads")
Replay.clearWrongDaySleep(for: day, store: badStore)
precondition(badStore.today.sleep == nil && badStore.history.first?.sleep == nil,
             "sync removes stale wrong-day sleep from UI and history")
precondition(badStore.today.sampleCount == 7 && badStore.history.first?.sampleCount == 7,
             "clearing wrong-day sleep preserves measurement samples")
let afternoon = ISO8601DateFormatter().date(from: "2026-09-05T13:09:00Z")!
let lateNight = SleepNight(totalMinutes: 550, deepMinutes: 60, lightMinutes: 490, wakeCount: 1,
    line: [], sleepStart: start, wakeAt: afternoon, intervals: nil)
precondition(Replay.sleepSummary(night: lateNight, day: day, store: badStore,
    oxygen: [:], respiration: [:])?.wakeAt == afternoon,
             "13:09 wake remains valid on its calendar day")
print("PASS: actual sleep summary preserves measurements and excludes between-segment wake time")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'models.swift').write_text(models)
    (path / 'helper.swift').write_text('import Foundation\nenum Replay {\n' + helper + '\n}')
    (path / 'main.swift').write_text(main)
    subprocess.run(['swiftc', str(path / 'models.swift'), str(path / 'helper.swift'), str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test')]).returncode)
