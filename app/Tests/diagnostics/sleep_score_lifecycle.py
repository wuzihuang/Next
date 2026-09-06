"""Execute the real score loader with a deterministic transport, plus cache wiring checks."""
from pathlib import Path
import subprocess,tempfile
APP=Path(__file__).resolve().parents[2]
def extract(path, marker):
 s=path.read_text();start=s.index(marker);opening=s.index('{',start);end=opening+1;depth=1
 while depth:
  depth+=(s[end]=='{')-(s[end]=='}');end+=1
 return s[start:end]
repo=APP/'NextBody/Services/Repository.swift';metrics=APP/'NextBody/Models/Metrics.swift'
source='import Foundation\nfunc L(_ s: String, _ args: CVarArg...) -> String { String(format:s,arguments:args) }\n'
source+=extract(metrics,'struct SleepScore:')+'\n'+extract(metrics,'enum SleepScoreGroup:')+'\n'
source+=r'''
enum SleepScoreLoadState { case idle, loading, ready, failed }
struct UserDay: Equatable {
 let key: String
 func adding(days: Int) -> UserDay {
  let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.timeZone=TimeZone(secondsFromGMT:0)
  return UserDay(key:f.string(from:f.date(from:key)!.addingTimeInterval(Double(days)*86400)))
 }
}
struct DailyMetrics { var day: UserDay;var sleepScore:SleepScore? }
@MainActor final class DataStore {
 var today=DailyMetrics(day:UserDay(key:"2026-09-06"))
 var history=[DailyMetrics(day:UserDay(key:"2026-09-05"))]
 var sleepScores:[String:SleepScore]=[:]
 var sleepScoreLoadState:SleepScoreLoadState = .idle
}
@MainActor enum HomeSnapshot { static var saves=0; static func save(from store:DataStore) { saves+=1 } }
@MainActor final class SupabaseClient {
 static let shared=SupabaseClient();static var owner:String?="A"
 static func currentUserIdSnapshot()->String? { owner }
 var fail=false;var query:[URLQueryItem]=[];var beforeResponse:(()->Void)?
 var rows:[[String:Any]]=[["user_day":"2026-09-06","score":87,"duration_score":77,"architecture_score":80,"recovery_score":99,"personal_weight":0,"inputs":["hrv_ms":67.8],"score_version":"sleep-v1.2","computed_at":"2026-09-06T11:56:14.123Z"]]
 enum Failure:Error {case offline}
 func select(_ table:String,query:[URLQueryItem]) async throws->[[String:Any]] {
  self.query=query;beforeResponse?();if fail {throw Failure.offline};return rows
 }
}
@MainActor final class Repository {
 let db=SupabaseClient.shared
 var readGeneration:UInt=0;var sessionGeneration:UInt=0;var sleepScoreGeneration:UInt=0
'''
for marker in ['func loadSleepScores(', 'private static func integer(', 'private static func decimal(', 'static func timestamp(']:
 source+=extract(repo,marker)+'\n'
source+='}\n'
source+=r'''
@MainActor func run() async throws {
 var failures=0
 func check(_ pass:Bool,_ name:String) {print("\(pass ? "PASS":"FAIL"): \(name)");if !pass {failures+=1}}
 let repo=Repository(),store=DataStore(),db=SupabaseClient.shared
 let day=store.today.day
 await repo.loadSleepScores(days:30,endingAt:day,into:store)
 check(store.sleepScores[day.key]?.score==87,"real loader reads server score")
 check(store.sleepScoreLoadState == .ready,"successful request publishes ready")
 check(HomeSnapshot.saves==1,"successful response saves durable cache")
 check(db.query.contains {$0.name=="user_day" && $0.value=="gte.2026-08-08"},"30-night query is exactly 30 dates")
 let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(store.sleepScores[day.key]!)) as! [String:Any]
 check(encoded["computedAt"] != nil,"score timestamp survives Codable")
 db.fail=true
 await repo.loadSleepScores(days:30,endingAt:day,into:store)
 check(store.sleepScores[day.key]?.score==87 && store.sleepScoreLoadState == .failed,"offline request preserves score with explicit failure")
 db.fail=false;store.sleepScores=[:]
 db.beforeResponse={SupabaseClient.owner="B"}
 await repo.loadSleepScores(days:30,endingAt:day,into:store)
 check(store.sleepScores.isEmpty,"previous account response never reaches new account")
 SupabaseClient.owner="A";store.sleepScores=[:];db.beforeResponse={repo.readGeneration += 1}
 await repo.loadSleepScores(days:30,endingAt:day,into:store)
 check(store.sleepScores[day.key]?.score==87,"unrelated raw-data read does not cancel score response")
 db.beforeResponse=nil
 let cancelled = Task { @MainActor in
  withUnsafeCurrentTask { $0?.cancel() }
  await repo.loadSleepScores(days:30,endingAt:day,into:store)
 }
 await cancelled.value
 check(store.sleepScoreLoadState == .idle,"cancelled successful transport exits loading state")
 db.rows=[]
 await repo.loadSleepScores(days:30,endingAt:day,into:store)
 check(store.sleepScores.isEmpty && store.today.sleepScore==nil,"successful empty response removes stale derived score")
 if failures>0 {exit(1)}
}
try await run()
'''
with tempfile.TemporaryDirectory(prefix='next-score-lifecycle-') as tmp:
 p=Path(tmp);(p/'main.swift').write_text(source)
 subprocess.run(['swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'test')],check=True)
 result=subprocess.run([str(p/'test')])
# These are wiring assertions, explicitly distinct from executed repository behavior.
checks={
 'account cleanup clears score dictionary':'sleepScores = [:]' in extract(APP/'NextBody/Services/DataStore.swift','func clearAccountDisplay('),
 'snapshot encodes score dictionary':'sleepScores' in extract(APP/'NextBody/Services/HomeSnapshot.swift','struct Payload:'),
 'snapshot restores score dictionary':'store.sleepScores' in extract(APP/'NextBody/Services/HomeSnapshot.swift','static func apply('),
 'daily cache encodes score':'sleepScore' in extract(metrics,'private enum CodingKeys:'),
 'detail cache cannot revive removed scores':'cached.sleepScore = store.sleepScores[day.key]' in extract(repo,'func loadDetail('),
 'normal and history sync refresh score':(APP/'NextBody/Services/Band/OriginDataSync.swift').read_text().count('loadSleepScores(')>=2,
}
for name,ok in checks.items():print(('PASS' if ok else 'FAIL')+': wiring — '+name)
raise SystemExit(result.returncode or int(not all(checks.values())))
