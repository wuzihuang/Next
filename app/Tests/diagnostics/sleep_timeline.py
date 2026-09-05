"""Compile the real Veepoo sleep timeline helpers against deterministic SDK model fixtures."""
from pathlib import Path
import tempfile,subprocess
APP = Path(__file__).resolve().parents[2]
s=(APP/'NextBody/Services/Band/VeepooBand.swift').read_text();start=s.index('    private struct SleepRecord');end=s.index('    /// 04B rule 04 · the night',start)
source='''import Foundation
struct SleepStageRun {let stage:Int;let minutes:Int;var offsetMinutes:Int?=nil}
struct SleepInterval {let start:Date;let end:Date}
struct SleepNight {let totalMinutes:Int;let deepMinutes:Int;let lightMinutes:Int;let wakeCount:Int;var line:[SleepStageRun]=[];var sleepStart:Date?=nil;var wakeAt:Date?=nil;var intervals:[SleepInterval]?=nil}
struct VPAccurateSleepModel {
 var sleepTime:String?; var wakeTime:String?; var stages:[Int]
 var sleepDuration:String?=nil; var deepDuration:String?=nil; var lightDuration:String?=nil;var otherDuration:String?=nil;var getUpTimes:String?=nil
 func parseSleepLine()->[[String:Any]]? { stages.map { ["type":NSNumber(value:$0)] } }
}
struct Adapter {
 static func instant(_ stamp:String?)->Date? { let f=DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm";return stamp.flatMap(f.date(from:)) }
'''+s[start:end].replace('private ','')+'''
}
func model(_ start:String,_ end:String,_ stages:[Int],total:Int?=nil)->VPAccurateSleepModel {
 .init(sleepTime:"2026-09-05 "+start,wakeTime:"2026-09-05 "+end,stages:stages,
 sleepDuration:String(total ?? stages.count),deepDuration:String(stages.filter{$0 == 0}.count),lightDuration:String(stages.filter{$0 == 1}.count))
}
func summary(_ models:[VPAccurateSleepModel])->SleepNight { Adapter.summarizeSleep(Adapter.sleepRecords(models))! }
func check(_ name:String,_ ok:Bool) {print("\\(ok ? "PASS" : "FAIL") \\(name)"); if !ok {exit(1)}}
let separated=[model("01:00","01:02",[0,0]),model("13:00","13:02",[0,0])]
let runs=Adapter.runs(from:separated)
check("real adapter stage runs preserve 12-hour gap",runs.count == 2 && runs.first?.offsetMinutes == 0 && runs.last?.offsetMinutes == 720)
let gap=summary(separated)
check("separate intervals exclude gap",gap.intervals?.count == 2 && gap.totalMinutes == 4)
let single=summary([model("03:59","13:09",Array(repeating:0,count:550),total:550)])
check("single SDK 550-minute total preserved",single.totalMinutes == 550)
let contained=summary([model("01:00","01:10",Array(repeating:0,count:10)),model("01:02","01:05",[1,1,1])])
check("contained fragments keep complete bounds and total",contained.totalMinutes == 10 && contained.deepMinutes == 10 && contained.lightMinutes == 0 && contained.wakeAt == Adapter.instant("2026-09-05 01:10"))
let overlap=summary([model("01:00","01:05",Array(repeating:0,count:5)),model("01:03","01:08",Array(repeating:1,count:5))])
check("partial overlaps deduplicate real-minute stages",overlap.totalMinutes == 8 && overlap.deepMinutes == 5 && overlap.lightMinutes == 3 && overlap.line.last?.offsetMinutes == 5 && overlap.intervals?.count == 1)
let plain=summary([model("01:00","01:05",[],total:5),model("01:03","01:08",[],total:5)])
check("unstaged overlap has union without fabricated stages",plain.totalMinutes == 8 && plain.line.isEmpty && plain.deepMinutes == 0 && plain.lightMinutes == 0)
let duplicate=summary([model("01:00","01:05",Array(repeating:0,count:5)),model("01:00","01:05",Array(repeating:0,count:5))])
check("identical SDK rows count once",duplicate.totalMinutes == 5 && duplicate.line.first?.minutes == 5)
let unknown=summary([model("01:00","01:03",[0,99,1])])
check("unknown minute does not shift later stages",unknown.line.count == 2 && unknown.line.last?.offsetMinutes == 2)
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(source);subprocess.run(['swiftc',str(p/'main.swift'),'-o',str(p/'run')],check=True);raise SystemExit(subprocess.run([str(p/'run')]).returncode)
