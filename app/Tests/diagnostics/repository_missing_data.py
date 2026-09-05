"""Compile actual Repository.load with deterministic server fixtures (no credentials)."""
from pathlib import Path
import subprocess, tempfile, os
APP = Path(__file__).resolve().parents[2]
def extract(path, marker):
    s=path.read_text(); start=s.index(marker); at=s.index('{',start); depth=1; end=at+1
    while depth:
        depth+=(s[end]=='{')-(s[end]=='}'); end+=1
    return s[start:end]
repo=APP/'NextBody/Services/Repository.swift'
source='import Foundation\nfunc L(_ s: String, _ args: CVarArg...) -> String { String(format: s, arguments: args) }\nstruct AppLanguage { static let shared = Self(); var swiftLocale: Locale { Locale(identifier: "en") } }\n'
for path in ['Models/Metrics.swift','Models/BodyBattery.swift','Services/Band/VitalSample.swift','Services/Band/DailyDirectionPolicy.swift','Services/Band/HomeLaunchPolicy.swift','Services/Band/VitalsTimelinePolicy.swift','Services/Band/MealResponseIndex.swift']:
    source+=(APP/'NextBody'/path).read_text()+'\n'
for marker in ['struct MealEntry:', 'struct WeighIn:', 'struct LiveVitals:']:
    source+=extract(APP/'NextBody/Services/DataStore.swift',marker)+'\n'
source+=extract(APP/'NextBody/Services/Band/BandService.swift','struct SleepStageRun:')+'\n'
if 'struct SleepInterval:' in (APP/'NextBody/Services/Band/BandService.swift').read_text():
    source+=extract(APP/'NextBody/Services/Band/BandService.swift','struct SleepInterval:')+'\n'
source+='''
final class DataStore {
 var today = DailyMetrics(day: UserDay.containing(Date()))
 var mealResponsePoints: [MealResponseIndex.Point] = []
 var history: [DailyMetrics] = []; var meals: [MealEntry] = []; var recentMeals: [MealEntry] = []
 var weighIns: [WeighIn] = []; var vitals = LiveVitals(); var isOffline = false
 func rebaseBodyBatteryPreview() {}
 func metrics(for day: UserDay) -> DailyMetrics? { day == today.day ? today : history.first { $0.day == day } }
}
struct HomeSnapshot { static func saveDetail(_ d: DailyMetrics, userId: String) {}; static func save(from s: DataStore) {} }
struct MealQueue { static let shared = Self(); func overlayPending(into s: DataStore, ownerUserId: String) {} }
struct WeighInQueue { static let shared = Self(); func flush() async {} }
@MainActor final class SupabaseClient {
 enum Failure: Error { case http(Int, String) }
 static let shared = SupabaseClient()
 static func currentUserIdSnapshot() -> String? { "fixture-user" }
 var mode = "modern"; var calls: [String] = []
 let day = UserDay.containing(Date()).key
 func select(_ table: String, query: [URLQueryItem]) async throws -> [[String: Any]] {
  calls.append(table)
  if mode == "offline-cached" { throw Failure.http(503, "offline") }
  if table == "daily_results" {
   if mode.hasPrefix("schema-"), let code = Int(mode.split(separator: "-").last!) { throw Failure.http(code, "column daily_results.result_revision does not exist") }
   if mode == "other-column" { throw Failure.http(400, "column daily_results.other_column does not exist") }
   if (mode == "old-schema" || mode == "legacy") && query.contains(where: { $0.value?.contains("result_revision") == true }) {
    throw Failure.http(400, "column daily_results.result_revision does not exist")
   }
   var row: [String: Any] = ["id":"fixture-result", "user_day":day, "reserve_score":72, "fuel_balance_kcal":-350]
   if mode != "old-schema" && mode != "legacy" { row["result_revision"] = "r1" }
   return [row]
  }
  if table == "day_fuel" {
   let row: [String: Any] = ["result_id":"fixture-result", "intake_state":"CONFIRMED", "kcal_in":650, "kcal_out":1000, "protein_in_g":30, "bmr_kcal":800, "active_kcal":200]
   let fields = Set((query.first { $0.name == "select" }?.value ?? "").split(separator: ",").map(String.init))
   return [row.filter { fields.contains($0.key) }]
  }
  if table == "reserve_daily" { return [["result_id":"fixture-result", "night_inputs":["hrv":52,"hrv_base":50,"rhr":58]]] }
  if table == "meals" { return [["id":"00000000-0000-0000-0000-000000000001", "user_day":day, "slot":"BREAKFAST", "logged_at":day+"T09:00:00Z", "text_input":"fixture breakfast", "kcal":650, "protein_g":30]] }
  if table == "sleep_nights", mode == "wrong-sleep-day" {
   let start = UserDay.containing(Date()).adding(days:1).start
   let stamp = ISO8601DateFormatter()
   return [["user_day":day,"total_minutes":410,"sleep_start":stamp.string(from:start),"wake_at":stamp.string(from:start.addingTimeInterval(5*3600))]]
  }
  if table == "sleep_nights", mode.hasPrefix("interval-") {
   let start = UserDay.containing(Date()).start
   let stamp = ISO8601DateFormatter()
   var raw: [String: Any] = ["hrv": [["ts":stamp.string(from:start.addingTimeInterval(3600)),"rmssd_ms":51.0]], "respiration":[["ts":stamp.string(from:start.addingTimeInterval(3600)),"breaths_per_minute":15.0]]]
   if mode == "interval-invalid" { raw["intervals"] = [["start":"invalid","end":"invalid"]] }
   if mode == "interval-empty" { raw["intervals"] = [] as [[String: Any]] }
   return [["user_day":day,"total_minutes":420,"sleep_start":stamp.string(from:start),"wake_at":stamp.string(from:start.addingTimeInterval(8*3600)),"raw":raw]]
  }
  if table == "oxygen_samples", mode.hasPrefix("interval-") {
   return [["ts":ISO8601DateFormatter().string(from:UserDay.containing(Date()).start.addingTimeInterval(3600)),"spo2":97]]
  }
  if table == "sleep_nights", mode == "stale-sleep" {
   let start = UserDay.containing(Date()).start
   let stamp = ISO8601DateFormatter()
   return [["user_day":day, "total_minutes":240, "sleep_start":stamp.string(from:start), "wake_at":stamp.string(from:start.addingTimeInterval(4*3600))]]
  }
  if table == "oxygen_samples", mode == "history-sleep" {
   return [["ts":ISO8601DateFormatter().string(from:UserDay.containing(Date()).start.addingTimeInterval(3600)),"spo2":98]]
  }
  if table == "sleep_nights", mode == "local-sleep" { return [] }
  if table == "sleep_nights", mode == "history-sleep" {
   let fields = query.first { $0.name == "select" }?.value ?? ""
   guard fields.contains("raw"), query.contains(where: { $0.name == "user_day" && $0.value == "gte." + UserDay.containing(Date()).adding(days: -3).key }) else { return [] }
   return (0...3).map { offset in
    let d = UserDay.containing(Date()).adding(days: -offset)
    let stamp = ISO8601DateFormatter()
    return ["user_day":d.key, "total_minutes":420 + offset, "sleep_start":stamp.string(from:d.start), "wake_at":stamp.string(from:d.start.addingTimeInterval(8*3600)), "raw":["intervals":[["start":stamp.string(from:d.start),"end":stamp.string(from:d.start.addingTimeInterval(3*3600))],["start":stamp.string(from:d.start.addingTimeInterval(4*3600)),"end":stamp.string(from:d.start.addingTimeInterval(8*3600))]], "line":[["stage":1,"minutes":30,"offset_minutes":240]], "hrv":[["ts":stamp.string(from:d.start.addingTimeInterval(59*60)),"rmssd_ms":51.0],["ts":stamp.string(from:d.start.addingTimeInterval(3.5*3600)),"rmssd_ms":55.0]], "respiration":[["ts":stamp.string(from:d.start.addingTimeInterval(3.5*3600)),"breaths_per_minute":17.0],["ts":stamp.string(from:d.start.addingTimeInterval(3600)),"breaths_per_minute":15.0],["ts":stamp.string(from:d.start.addingTimeInterval(1800)),"breaths_per_minute":255.0],["ts":stamp.string(from:d.start.addingTimeInterval(2400)),"breaths_per_minute":0.0],["ts":stamp.string(from:d.start.addingTimeInterval(9*3600)),"breaths_per_minute":18.0]]]]
   }
  }
  if table == "raw_samples", mode == "history-sleep", query.first(where: { $0.name == "select" })?.value?.contains("temp") == true {
   guard query.contains(where: { $0.name == "ts" && $0.value == "gte." + ISO8601DateFormatter().string(from: UserDay.containing(Date()).adding(days: -4).start) }) else { return [] }
   return (0...3).map { ["ts":ISO8601DateFormatter().string(from: UserDay.containing(Date()).adding(days: -$0).start),"temp":33.6] }
  }
  if table == "sleep_nights" { return [["user_day":day, "total_minutes":420, "deep_minutes":120, "light_minutes":300, "wake_count":1]] }
  return []
 }
 func callFunction(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
  calls.append(name)
  if mode.hasPrefix("function-") { throw Failure.http(Int(mode.split(separator: "-").last!)!, "unavailable") }
  if mode == "missing-function" || mode == "legacy" { throw Failure.http(404, "Requested function was not found") }
  let vals: [String: Double] = ["intakeKcal":650, "burnKcal":1000, "deltaKcal":-350, "proteinG":30, "sleepMinutes":420, "nightHRV":52, "hrvBaseline":50, "nightRHR":58]
  if mode == "modern-null" {
   return ["ok":true,"data":vals.map { ["metric":$0.key,"points":[["dayKey":day,"value":NSNull(),"resultRevision":"r1"]]] }]
  }
  return ["ok":true, "data": vals.map { ["metric":$0.key, "points":[["dayKey":day, "value":$0.value, "resultRevision":mode == "revision-mismatch" ? "r2" : "r1"]]] }]
 }
 func rpc(_ name: String, args: [String: Any]) async throws -> Any {
  calls.append(name)
  if mode.hasPrefix("status-"), let code = Int(mode.split(separator: "-").last!) { throw Failure.http(code, "unavailable") }
  if mode == "missing-status" { throw Failure.http(404, "Could not find calculation_status") }
  return [["user_day":day,"result_revision":mode == "status-mismatch" ? "r2" : "r1"]]
 }
}
@MainActor final class Repository {
 let db = SupabaseClient.shared
 private var readGeneration: UInt = 0
'''
for marker in ['func load(days:', 'private func merge(', 'static func overnightOxygen(', 'static func sleepRespiration(', 'static func sleepHRV(', 'static func opticalResponse(', 'private static func numberStatic(', 'private static func sleepOnWakeDay(', 'static func timestamp(', 'static func isMissingReadCapability(', 'private func selectDailyResultsCompat(', 'private func metricReadIfAvailable(', 'private func calculationStatusIfAvailable(', 'private func number(', 'private func selectByResultId(', 'private func selectTrainingExtras(', 'private static func resultIdChunks(']:
    source+=extract(repo,marker)+'\n'
source+='''
}
let mode = CommandLine.arguments[1]
SupabaseClient.shared.mode = mode
let store = DataStore()
if mode == "offline-cached" || mode == "local-sleep" {
 store.today.bodyBattery = 72
 store.today.sleep = SleepSummary(totalMinutes: 420, deepMinutes: 120, lightMinutes: 300, wakeCount: 1)
 store.meals = [MealEntry(id: UUID(), day: store.today.day, at: Date(), slot: .breakfast, status: .confirmed, text: "fixture breakfast", kcal: 650, protein: 30, carb: 60, fat: 20)]
}
if mode == "history-sleep" || mode == "stale-sleep" {
 let start = store.today.day.start
 store.today.sleep = SleepSummary(totalMinutes: 420, deepMinutes: 120, lightMinutes: 300, wakeCount: 1,
  sleepStart: start, wakeAt: start.addingTimeInterval(8*3600),
  spo2: [OvernightOxygenPoint(ts: start.addingTimeInterval(3600), percent: 97)],
  respiration: [SleepRespirationPoint(ts: start.addingTimeInterval(7200), breathsPerMinute: 16), SleepRespirationPoint(ts: start.addingTimeInterval(3600), breathsPerMinute: 14)], hrv: [SleepHRVPoint(ts: start.addingTimeInterval(59*60), rmssdMS: 53)])
}
if mode == "wrong-sleep-day" {
 let start = store.today.day.adding(days:1).start
 store.today.sleep = SleepSummary(totalMinutes:410,deepMinutes:100,lightMinutes:310,wakeCount:0,sleepStart:start,wakeAt:start.addingTimeInterval(5*3600))
}
await Repository().load(days: mode == "history-sleep" ? 3 : 1, endingAt: store.today.day, into: store)
let rejected = mode.hasPrefix("function-") || mode.hasPrefix("status-") || mode.hasSuffix("mismatch") || mode.hasPrefix("schema-") || mode == "other-column"
let absentHRV = Repository.sleepHRV(raw: [:], start: store.today.day.start, wake: store.today.day.end)
let emptyHRV = Repository.sleepHRV(raw: ["hrv": []], start: store.today.day.start, wake: store.today.day.end)
precondition(absentHRV == nil && emptyHRV?.isEmpty == true, "legacy nil and measured empty HRV must remain distinct")
let checks = mode == "wrong-sleep-day" ? [("sleep from a different wake date is not displayed", store.today.sleep == nil)] : mode.hasPrefix("interval-") ? [("legacy missing intervals use recorded window; explicit empty/invalid intervals do not", {
 let sleep = store.today.sleep
 let legacy = mode == "interval-missing"
 return sleep?.containsSleepTimestamp(store.today.day.start.addingTimeInterval(3600)) == legacy &&
  (sleep?.intervals == nil) == legacy && sleep?.hrv?.count == (legacy ? 1 : 0) && sleep?.respiration?.count == (legacy ? 1 : 0) && sleep?.spo2.count == (legacy ? 1 : 0)
}())] : mode == "stale-sleep" ? [("remote partial night cannot overwrite completed local night", store.today.sleep?.totalMinutes == 420 && store.today.sleep?.wakeAt == store.today.day.start.addingTimeInterval(8*3600) && store.today.sleep?.respiration?.first?.breathsPerMinute == 16)] : mode == "history-sleep" ? [("all requested days retain raw sleep, respiration and temperature", (0...3).allSatisfy { (offset: Int) in
 let m = store.metrics(for: store.today.day.adding(days: -offset))
 return m?.sleep?.hrv?.count == 1 && m?.sleep?.hrv?.first?.rmssdMS == (offset == 0 ? 53 : 51) && m?.sleep?.hrv?.first?.ts == m?.day.start.addingTimeInterval(59*60) && m?.sleep?.totalMinutes == 420 + offset && m?.sleep?.intervals?.count == 2 && m?.sleep?.line.first?.offsetMinutes == 240 && m?.sleep?.respiration?.count == (offset == 0 ? 2 : 1) && m?.sleep?.respiration?.first?.breathsPerMinute == (offset == 0 ? 14 : 15) && m?.vitalsCurve.first?.temp == 33.6 && (offset != 0 || m?.sleep?.spo2.first?.percent == 97 && m?.sleep?.spo2.count == 1 && m?.sleep?.respiration?.map { $0.breathsPerMinute }.reduce(0, +) == 30)
})] : mode == "modern-null" ? [("formal null is not replaced by legacy values", store.today.sleep?.totalMinutes == 420 && store.today.eIn == nil && store.today.eOutNow == nil && store.today.proteinIn == 30 && store.today.balance == nil && store.today.nightInputs?.hrv == nil && store.meals.count == 1 && store.today.bodyBattery == 72)] : rejected ? [("reject incomplete read", store.today.sleep == nil && store.meals.isEmpty && store.today.bodyBattery == nil)] : [("sleep", store.today.sleep?.totalMinutes == 420), ("food", store.meals.count == 1), ("body battery", store.today.bodyBattery == 72), ("stored fuel and night inputs", mode == "offline-cached" || (store.today.eIn == 650 && store.today.eOutNow == 1000 && store.today.proteinIn == 30 && store.today.balance == -350 && store.today.nightInputs?.hrv == 52))]
for (name, ok) in checks { print("\\(ok ? "PASS" : "FAIL"): \\(name) remains visible with \\(mode) backend") }
print("requests: " + SupabaseClient.shared.calls.joined(separator: ", "))
exit(checks.allSatisfy { $0.1 } ? 0 : 1)
'''
with tempfile.TemporaryDirectory(prefix='next-repository-repro-') as tmp:
    p=Path(tmp); (p/'main.swift').write_text(source)
    result=subprocess.run(['swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'repro')],capture_output=True,text=True)
    if result.returncode: print(result.stderr); raise SystemExit(result.returncode)
    import sys
    modes=sys.argv[1:] or ['modern','legacy','old-schema','missing-function','missing-status','offline-cached','function-401','function-403','function-500','status-401','status-403','status-500','revision-mismatch','status-mismatch','schema-401','schema-403','schema-500','other-column','modern-null','history-sleep','local-sleep','stale-sleep','interval-missing','interval-empty','interval-invalid','wrong-sleep-day']
    failed=False
    for mode in modes:
        result=subprocess.run([str(p/'repro'),mode],env={**os.environ,'TZ':'UTC'})
        failed|=result.returncode != 0
    raise SystemExit(int(failed))
