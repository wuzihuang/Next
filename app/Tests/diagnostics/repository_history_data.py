"""Compile actual Repository.loadHistorySummaries with deterministic server fixtures (no credentials)."""
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
for path in ['Models/Metrics.swift','Models/BodyBattery.swift','Services/Band/VitalSample.swift','Services/Band/DailyDirectionPolicy.swift','Services/Band/HomeLaunchPolicy.swift','Services/Band/VitalsTimelinePolicy.swift']:
    source+=(APP/'NextBody'/path).read_text()+'\n'
for marker in ['struct MealEntry:', 'struct WeighIn:', 'struct LiveVitals:']:
    source+=extract(APP/'NextBody/Services/DataStore.swift',marker)+'\n'
source+=extract(APP/'NextBody/Services/Band/BandService.swift','struct SleepStageRun:')+'\n'
if 'struct SleepInterval:' in (APP/'NextBody/Services/Band/BandService.swift').read_text():
    source+=extract(APP/'NextBody/Services/Band/BandService.swift','struct SleepInterval:')+'\n'
source+='''
final class DataStore {
 var today = DailyMetrics(day: UserDay.containing(Date()))
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
 let day = UserDay.containing(Date()).adding(days: -1).key
 func select(_ table: String, query: [URLQueryItem]) async throws -> [[String: Any]] {
  calls.append(table)
  if mode == "offline-cached" { throw Failure.http(503, "offline") }
  if table == "daily_results" {
   if (mode == "old-schema" || mode == "legacy") && query.contains(where: { $0.value?.contains("result_revision") == true }) {
    throw Failure.http(400, "column daily_results.result_revision does not exist")
   }
   var row: [String: Any] = ["id":"fixture-result", "user_day":day, "reserve_score":72, "fuel_balance_kcal":-350]
   if mode != "old-schema" { row["result_revision"] = "r1" }
   return [row]
  }
  if table == "day_fuel" { return [["result_id":"fixture-result", "intake_state":"CONFIRMED", "kcal_in":650, "kcal_out":1000, "protein_in_g":30, "bmr_kcal":800, "active_kcal":200]] }
  if table == "meals" { return [["id":"00000000-0000-0000-0000-000000000001", "user_day":day, "slot":"BREAKFAST", "logged_at":day+"T09:00:00Z", "text_input":"fixture breakfast", "kcal":650]] }
  if table == "sleep_nights" { return [["user_day":day, "total_minutes":420, "deep_minutes":120, "light_minutes":300, "wake_count":1]] }
  return []
 }
 func callFunction(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
  calls.append(name)
  if mode.hasPrefix("function-") { throw Failure.http(Int(mode.split(separator: "-").last!)!, "unavailable") }
  if mode == "missing-function" { throw Failure.http(404, "Requested function was not found") }
  let vals: [String: Double] = ["intakeKcal":650, "burnKcal":1000, "deltaKcal":-350, "proteinG":30, "sleepMinutes":420]
  return ["ok":true, "data": vals.map { ["metric":$0.key, "points":[["dayKey":day, "value":$0.value, "resultRevision":mode == "revision-mismatch" ? "r2" : "r1"]]] }]
 }
 func rpc(_ name: String, args: [String: Any]) async throws -> Any {
  calls.append(name)
  if ["status-401", "status-403", "status-500"].contains(mode) { throw Failure.http(Int(mode.split(separator: "-").last!)!, "unavailable") }
  if mode == "missing-status" || mode == "legacy" { throw Failure.http(404, "Could not find calculation_status") }
  return [["user_day":day,"result_revision":mode == "status-mismatch" ? "r2" : "r1"]]
 }
}
@MainActor final class Repository {
 let db = SupabaseClient.shared
 private var readGeneration: UInt = 0
 private var summaryRevisions: [String: [String: String]] = [:]
'''
markers = ['func loadHistorySummaries(', 'private static func sleepOnWakeDay(', 'static func timestamp(', 'private func number(', 'private func selectByResultId(', 'private static func resultIdChunks(']
for optional in ['private func selectDailyResultsCompat(', 'private func calculationStatusIfAvailable(', 'static func isMissingReadCapability(']:
    if optional in repo.read_text(): markers.append(optional)
for marker in markers:
    source+=extract(repo,marker)+'\n'
source+='''
}
let mode = CommandLine.arguments[1]
SupabaseClient.shared.mode = mode
let store = DataStore()
if mode == "offline-cached" {
 var cached = DailyMetrics(day: store.today.day.adding(days: -1))
 cached.bodyBattery = 72; cached.balance = -350; store.history = [cached]
 store.today.bodyBattery = 72
 store.today.sleep = SleepSummary(totalMinutes: 420, deepMinutes: 120, lightMinutes: 300, wakeCount: 1)
 store.meals = [MealEntry(id: UUID(), day: store.today.day, at: Date(), slot: .breakfast, status: .confirmed, text: "fixture breakfast", kcal: 650, protein: 30, carb: 60, fat: 20)]
}
await Repository().loadHistorySummaries(days: 182, endingAt: store.today.day, into: store)
let rejected = mode.hasPrefix("status-") || mode.hasSuffix("mismatch")
let restored = store.history.contains { $0.bodyBattery == 72 && $0.balance == -350 }
let checks = [("historical battery and fuel summary", rejected ? !restored : restored)]
for (name, ok) in checks { print("\\(ok ? "PASS" : "FAIL"): \\(name) remains visible with \\(mode) backend") }
print("requests: " + SupabaseClient.shared.calls.joined(separator: ", "))
exit(checks.allSatisfy { $0.1 } ? 0 : 1)
'''
with tempfile.TemporaryDirectory(prefix='next-repository-repro-') as tmp:
    p=Path(tmp); (p/'main.swift').write_text(source)
    result=subprocess.run(['swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'repro')],capture_output=True,text=True)
    if result.returncode: print(result.stderr); raise SystemExit(result.returncode)
    import sys
    modes=sys.argv[1:] or ['modern','old-schema','missing-status','legacy','offline-cached','status-401','status-403','status-500','status-mismatch']
    failed=False
    for mode in modes:
        result=subprocess.run([str(p/'repro'),mode],env={**os.environ,'TZ':'UTC'})
        failed|=result.returncode != 0
    raise SystemExit(int(failed))
