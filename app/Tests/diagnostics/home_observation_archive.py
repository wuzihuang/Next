#!/usr/bin/env python3
"""Exercise real HomeSnapshot archive save/hydrate using isolated app service doubles."""
from pathlib import Path
import subprocess
import tempfile

app = Path(__file__).resolve().parents[2]
stubs = r'''
import Foundation
struct UserDay: Codable, Equatable, Comparable {
 let date: Date
 var key: String { String(Int(date.timeIntervalSince1970)) }
 static func containing(_ date: Date) -> Self { Self(date: Calendar.current.startOfDay(for: date)) }
 func adding(days: Int) -> Self { Self(date: date.addingTimeInterval(Double(days) * 86400)) }
 static func < (a: Self, b: Self) -> Bool { a.date < b.date }
}
typealias TrainingSegment = Int
typealias LoadPoint = Int
typealias ReserveDrivers = Int
typealias ReserveSample = Int
typealias NightInputs = Int
typealias TheCall = Int
typealias MealEntry = Int
typealias LiveVitals = Int
struct Profile: Codable { func restoringHealthSync() -> Self { self } }
struct SleepRespirationPoint: Codable, Equatable { var ts: Date; var breathsPerMinute: Double }
struct OvernightOxygenPoint: Codable, Equatable { var ts: Date; var percent: Int }

struct SleepInterval: Codable { var start: Date; var end: Date }
struct SleepSummary: Codable {
 var line: [Int] = []
 var intervals: [SleepInterval]? = nil
 var totalMinutes: Int
 var sleepStart: Date?
 var wakeAt: Date?
 var spo2: [OvernightOxygenPoint] = []
 var respiration: [SleepRespirationPoint]? = nil
 var hrv: [SleepHRVPoint]? = nil
 var hrvInvalidatedMinutes: [Date: Date]? = nil
 func containsSleepTimestamp(_ at: Date) -> Bool {
  if let intervals { return intervals.contains { at >= $0.start && at < $0.end } }
  guard let sleepStart, let wakeAt else { return false }; return at >= sleepStart && at < wakeAt
 }
}
struct DailyMetrics: Codable {
 let day: UserDay
 var optimalZone: ClosedRange<Double>?
 var segments: [Int] = []
 var loadCurve: [Int] = []
 var peakHR: Int?
 var reserveDrivers: Int?
 var reserveCurve: [Int] = []
 var vitalsCurve: [VitalSample] = []
 var nightInputs: Int?
 var sleep: SleepSummary?
 var sleepScore: SleepScore?
 var bmrFull: Double?
 var proteinIn: Int?
 var carbIn: Int?
 var fatIn: Int?
 var serverCall: Int?
}
struct BandState { var batteryPercent: Int?; var firmware = "" }
@MainActor final class DataStore {
 var today = DailyMetrics(day: UserDay.containing(Date()))
 var history: [DailyMetrics] = []
 var sleepScores: [String: SleepScore] = [:]
 var sleepScoreLoadState: SleepScoreLoadState = .idle
 var meals: [Int] = []
 var recentMeals: [Int] = []
 var vitals = 0
 var profile = Profile()
 var lastSync: Date?
 var boundAt: Date?
 var band = BandState()
 var netFatMass12w: Double?
 var netLeanMass12w: Double?
 var bodyFatPercent: Double?
 func rebaseBodyBatteryPreview(at: Date) {}
}
@MainActor enum WidgetGlancePublisher { static func publish(from store: DataStore, numbersAt: Date) {} }
enum Band { static let allowsSeed = false }
@MainActor enum SessionKeychain { static var userId: String?; static var accessToken: String? }
enum HomeLaunchPolicy {
 static func jwtSubject(_ token: String) -> String? { nil }
 static func shouldPaintToday(snapshotDayKey: String, currentDayKey: String) -> Bool { snapshotDayKey == currentDayKey }
}
@MainActor enum SupabaseClient { static func currentUserIdSnapshot() -> String? { SessionKeychain.userId } }
@MainActor struct MealQueue {
 static let shared = MealQueue()
 func overlayPending(into store: DataStore, ownerUserId: String) {}
}
'''
tests = r'''
@main struct ArchiveTests {
 @MainActor static func main() throws {
  let account = "archive-test-" + UUID().uuidString
  let other = "archive-other-" + UUID().uuidString
  let db = try LocalDataStore.shared()
  defer { try? db.purge(account: account); try? db.purge(account: other) }
  let now = Date()
  let day = UserDay.containing(now)
  let prior = day.adding(days: -40)
  let ts = day.date.addingTimeInterval(60)
  var night = SleepSummary(totalMinutes: 480, sleepStart: ts, wakeAt: ts.addingTimeInterval(28800),
    spo2: [.init(ts: ts, percent: 97)], respiration: [.init(ts: ts, breathsPerMinute: 15)])
  night.hrv = [.init(ts: ts, rmssdMS: 51)]
  night.line = [1, 2, 3]
  night.intervals = [.init(start: ts, end: ts.addingTimeInterval(1800)), .init(start: ts.addingTimeInterval(7200), end: ts.addingTimeInterval(28800))]
  try HomeSnapshot.saveBandObservations(day: day, samples: [.init(ts: ts, hr: 70, stress: nil, temp: 36.5, met: 6, hrv: 200)], sleep: night, userId: account)
  try HomeSnapshot.saveBandObservations(day: day, samples: [.init(ts: ts, hr: nil, stress: 20)], sleep: nil, userId: account)
  try HomeSnapshot.saveBandObservations(day: day, samples: [.init(ts: ts, hr: nil, stress: nil,
    hrvValid: false, hrvObservedAt: now)], sleep: nil, userId: account)
  try HomeSnapshot.saveBandObservations(day: day, samples: [.init(ts: ts, hr: nil, stress: nil,
    hrv: 200)], sleep: nil, userId: account)
  var refreshed = night
  refreshed.respiration = nil
  refreshed.hrv = [.init(ts: ts, rmssdMS: 52), .init(ts: ts.addingTimeInterval(3600), rmssdMS: 59), .init(ts: ts.addingTimeInterval(40000), rmssdMS: 60)]
  refreshed.spo2 = []
  refreshed.line = []
  refreshed.intervals = nil
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: refreshed, userId: account)
  var priorNight = night
  priorNight.sleepStart = prior.date.addingTimeInterval(60)
  priorNight.wakeAt = prior.date.addingTimeInterval(28860)
  try HomeSnapshot.saveBandObservations(day: prior, samples: [], sleep: priorNight, userId: account)
  let wrongDay = day.adding(days: -1)
  let wrongArchive = HomeSnapshot.BandDay(day: wrongDay, samples: [.init(ts: wrongDay.date, hr: 65, stress: nil)], sleep: night)
  let wrongBytes = try JSONEncoder().encode(wrongArchive)
  try db.writeObservationDocument(account: account, key: "band-day:" + wrongDay.key, data: wrongBytes)
  try HomeSnapshot.saveBandObservations(day: day, samples: [.init(ts: ts, hr: 99, stress: nil)], sleep: nil, userId: other)
  SessionKeychain.userId = account
  let cached = DataStore()
  var wrongCached = DailyMetrics(day: wrongDay)
  wrongCached.sleep = night
  cached.history = [wrongCached]
  let score = SleepScore(score: 87, duration: 77, architecture: 80, recovery: 99, inputs: ["hrv_coverage": 0.5158], version: "sleep-v1.2", computedAt: now)
  cached.sleepScores[day.key] = score
  cached.today.sleepScore = score
  cached.today.serverCall = 42
  cached.today.reserveCurve = [9]
  precondition(HomeSnapshot.save(from: cached, now: now))
  let store = DataStore()
  HomeSnapshot.hydrate(into: store, now: now)
  precondition(store.sleepScores[day.key] == score && store.today.sleepScore == score, "offline hydration restores score and evidence timestamp")
  precondition(store.sleepScoreLoadState == .idle, "cached score is not represented as fresh server result")
  let snapshotData = try db.readDocument(account: account, key: "home")!
  var legacy = try JSONSerialization.jsonObject(with: snapshotData) as! [String: Any]
  legacy.removeValue(forKey: "sleepScores")
  let oldPayload = try JSONDecoder().decode(HomeSnapshot.Payload.self, from: JSONSerialization.data(withJSONObject: legacy))
  precondition(oldPayload.sleepScores == nil, "pre-score snapshots must remain decodable")
  precondition(store.today.serverCall == 42 && store.today.reserveCurve == [9], "archive must preserve derived metrics")
  precondition(store.history.first(where: { $0.day == wrongDay })?.sleep == nil, "wrong wake-day sleep must be hidden")
  precondition(store.history.first(where: { $0.day == wrongDay })?.vitalsCurve.first?.hr == 65, "wrong-day sleep cleanup must retain vitals")
  let unchangedArchive = try db.readObservationDocument(account: account, key: "band-day:" + wrongDay.key)
  precondition(unchangedArchive == wrongBytes, "hydrate must preserve original archive")
  try HomeSnapshot.saveBandObservations(day: wrongDay, samples: [], sleep: nil, userId: account)
  let repairedData = try db.readObservationDocument(account: account, key: "band-day:" + wrongDay.key)!
  let repairedArchive = try JSONDecoder().decode(HomeSnapshot.BandDay.self, from: repairedData)
  precondition(repairedArchive.sleep == nil, "nil refresh must not retain invalid old day")
  precondition(store.today.vitalsCurve.count == 1)
  precondition(store.today.vitalsCurve[0].hr == 70 && store.today.vitalsCurve[0].stress == 20 && store.today.vitalsCurve[0].temp == 36.5)
  precondition(store.today.vitalsCurve[0].met == 6, "auxiliary reads and hydration must preserve MET")
  precondition(store.today.vitalsCurve[0].hrv == nil && store.today.vitalsCurve[0].hrvValid == false,
    "explicit HRV revocation must survive archive, hydration, and stale legacy reads")
  precondition(store.today.vitalsCurve[0].hrvObservedAt == now)
  precondition(store.today.sleep?.respiration?.first?.breathsPerMinute == 15)
  precondition(store.today.sleep?.hrv?.count == 1 && store.today.sleep?.hrv?.first?.rmssdMS == 52, "sleep HRV must merge by exact minute and filter actual intervals")
  precondition(store.today.sleep?.spo2.first?.percent == 97)
  precondition(store.today.sleep?.line == [1, 2, 3], "empty refresh must retain stage line")
  precondition(store.today.sleep?.intervals?.count == 2, "summary refresh must retain intervals")
  var revokedNight = night
  revokedNight.hrv = []
  revokedNight.hrvInvalidatedMinutes = [ts: now]
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: revokedNight, userId: account)
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: night, userId: account)
  let revokedStore = DataStore()
  HomeSnapshot.hydrate(into: revokedStore, now: now)
  precondition(revokedStore.today.sleep?.hrv?.isEmpty == true,
    "archived revocation must reject a legacy minute on repeated save and hydrate")
  precondition(revokedStore.today.sleep?.hrvInvalidatedMinutes?[ts] == now)
  var recoveredNight = night
  recoveredNight.hrv = [.init(ts: ts, rmssdMS: 45, observedAt: now.addingTimeInterval(60))]
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: recoveredNight, userId: account)
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: revokedNight, userId: account)
  var staleNight = night
  staleNight.hrv = [.init(ts: ts, rmssdMS: 200, observedAt: now.addingTimeInterval(-60))]
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: staleNight, userId: account)
  let recoveredStore = DataStore()
  HomeSnapshot.hydrate(into: recoveredStore, now: now)
  precondition(recoveredStore.today.sleep?.hrv?.first?.rmssdMS == 45,
    "later valid evidence survives both a stale valid point and an older revocation")
  let minuteArchiveData = try db.readObservationDocument(account: account, key: "band-day:" + day.key)!
  let minuteArchive = try JSONDecoder().decode(HomeSnapshot.BandDay.self, from: minuteArchiveData)
  precondition(minuteArchive.sleep?.hrv?.first?.observedAt == now.addingTimeInterval(60))
  precondition(minuteArchive.sleep?.hrvInvalidatedMinutes?[ts] == now)
  var overlappingOldNight = staleNight
  overlappingOldNight.sleepStart = ts.addingTimeInterval(-60)
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: overlappingOldNight, userId: account)
  let overlappingStore = DataStore()
  HomeSnapshot.hydrate(into: overlappingStore, now: now)
  precondition(overlappingStore.today.sleep?.hrv?.first?.rmssdMS == 45,
    "an overlapping window revision cannot replace newer measured HRV with stale values")
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: recoveredNight, userId: account)
  let partial = SleepSummary(totalMinutes: 120, sleepStart: ts.addingTimeInterval(60), wakeAt: ts.addingTimeInterval(7260))
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: partial, userId: account)
  let partialRefresh = DataStore()
  HomeSnapshot.hydrate(into: partialRefresh, now: now)
  precondition(partialRefresh.today.sleep?.totalMinutes == 480, "contained partial refresh must not shrink complete sleep")
  precondition(store.history.first(where: { $0.day == prior })?.sleep?.totalMinutes == 480)
  let oldKey = "band-day:" + prior.key
  let oldData = try db.readObservationDocument(account: account, key: oldKey)!
  var oldObject = try JSONSerialization.jsonObject(with: oldData) as! [String: Any]
  var oldSleep = oldObject["sleep"] as! [String: Any]
  oldSleep.removeValue(forKey: "respiration")
  oldSleep.removeValue(forKey: "hrv")
  oldObject["sleep"] = oldSleep
  try db.writeObservationDocument(account: account, key: oldKey, data: JSONSerialization.data(withJSONObject: oldObject))
  try db.pruneCache(maxBytes: 0)
  let uncached = DataStore()
  HomeSnapshot.hydrate(into: uncached, now: now)
  precondition(uncached.today.sleep?.totalMinutes == 480, "cache eviction must not erase measurements")
  precondition(uncached.history.first(where: { $0.day == prior })?.sleep?.totalMinutes == 480, "archives before respiration must decode")
  precondition(uncached.history.first(where: { $0.day == prior })?.sleep?.respiration == nil)
  precondition(uncached.history.first(where: { $0.day == prior })?.sleep?.hrv == nil)
  var nextNight = SleepSummary(totalMinutes: 300, sleepStart: ts.addingTimeInterval(30000), wakeAt: ts.addingTimeInterval(48000))
  nextNight.respiration = [.init(ts: ts.addingTimeInterval(60), breathsPerMinute: 16)]
  try HomeSnapshot.saveBandObservations(day: day, samples: [], sleep: nextNight, userId: account)
  let newWindow = DataStore()
  HomeSnapshot.hydrate(into: newWindow, now: now)
  precondition(newWindow.today.sleep?.spo2.isEmpty == true, "different sleep windows must not inherit oxygen points")
  precondition(newWindow.today.sleep?.respiration?.count == 1)
  SessionKeychain.userId = other
  let isolated = DataStore()
  HomeSnapshot.hydrate(into: isolated, now: now)
  precondition(isolated.sleepScores.isEmpty && isolated.today.sleepScore == nil, "other account must not restore cached scores")
  precondition(isolated.today.vitalsCurve.first?.hr == 99 && isolated.today.sleep == nil)
  print("PASS: archive merges measurements and sleep streams, restores missing history after cache eviction, preserves derived metrics, isolates accounts")
 }
}
'''
def extract(marker):
    source = (app / 'NextBody/Models/Metrics.swift').read_text()
    start = source.index(marker); pos = source.index('{', start) + 1; depth = 1
    while depth:
        depth += (source[pos] == '{') - (source[pos] == '}'); pos += 1
    return source[start:pos]
score_models = 'enum SleepScoreGroup { case duration, architecture, recovery, regularity }\n' + extract('struct SleepScore:') + '\n' + extract('enum SleepScoreLoadState') + '\n' + extract('struct SleepHRVPoint:')
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / 'Harness.swift'
    source.write_text(stubs + '\n' + score_models + '\n' + (app / 'NextBody/Services/Band/VitalSample.swift').read_text() + '\n' + (app / 'NextBody/Services/Band/VitalsTimelinePolicy.swift').read_text() + '\n' + (app / 'NextBody/Services/HomeSnapshot.swift').read_text() + '\n' + tests)
    result = subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', str(source), str(app / 'NextBody/Services/Storage/LocalDataStore.swift'), '-o', str(root / 'test')], text=True, capture_output=True)
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
    run = subprocess.run([str(root / 'test')], capture_output=True, text=True)
    print(run.stdout, end='')
    if run.returncode:
        print(run.stderr)
        import re
        match = re.search(r'Harness.swift:(\d+)', run.stderr)
        if match: print(source.read_text().splitlines()[int(match[1]) - 1])
        raise SystemExit(1)
