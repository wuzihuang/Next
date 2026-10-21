from pathlib import Path
import subprocess
import tempfile


APP = Path(__file__).resolve().parents[2]


def extract(path, marker):
    source = path.read_text()
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


metrics = APP / "NextBody/Models/Metrics.swift"
board = APP / "NextBody/Features/Vitals/SleepRangeBoard.swift"
source = """
import Foundation
func L(_ text: String, _ args: CVarArg...) -> String {
    String(format: text, arguments: args)
}
"""
source += extract(metrics, "struct SleepScore:") + "\n"
source += extract(metrics, "enum SleepScoreGroup:") + "\n"
source += extract(metrics, "enum SleepContributor:") + "\n"
source += extract(board, "extension SleepScore {") + "\n"
model_source = source
source += """
struct UserDay { let key: String }
struct SleepSummary { let sleepStart: Date?; let wakeAt: Date? }
"""
source += extract(board, "struct SleepScheduleNight:") + "\n"
source += """
var failures = 0
func check(_ passed: Bool, _ name: String) {
    print("\\(passed ? "PASS" : "FAIL"): \\(name)")
    if !passed { failures += 1 }
}

let legacy = SleepScore(score: 88, duration: 50, architecture: 100, recovery: 100,
                        regularity: 100, version: "sleep-v1.3")
check(SleepScoreGroup.allCases.map { legacy.effectiveWeight(of: $0) } == [25, 25, 35, 15],
      "cached legacy scores keep the weights that produced them")
var current = SleepScore(score: 60, duration: 50, architecture: 100, recovery: 100,
                         regularity: 100, inputs: [
                            "duration_min": 300,
                            "weight_duration": 50, "weight_architecture": 20,
                            "weight_recovery": 20, "weight_regularity": 10,
                            "duration_score_cap": 60, "duration_cap_applied": 1,
                            "score_before_duration_cap": 75
                         ], version: "sleep-v2.0")
check(SleepScoreGroup.allCases.map { current.effectiveWeight(of: $0) } == [50, 20, 20, 10],
      "the explanation uses weights carried by the server result")
check(current.appliedDurationCap == 60 && legacy.appliedDurationCap == nil,
      "a capped score has an explanation without inventing one for legacy scores")
var uncapped = current
uncapped.inputs["duration_cap_applied"] = 0
check(uncapped.appliedDurationCap == nil, "the limit note only appears when the limit changed the score")
var malformed = current
malformed.inputs["duration_score_cap"] = .infinity
check(malformed.appliedDurationCap == nil, "an invalid limit cannot crash display formatting")
malformed.inputs["duration_score_cap"] = 101
check(malformed.appliedDurationCap == nil, "out-of-scale limits are not displayed")
current.regularity = nil
check(abs((current.effectiveWeight(of: .duration) ?? 0) - 50.0 / 90 * 100) < 0.001 &&
      current.effectiveWeight(of: .regularity) == nil,
      "missing groups renormalise the new weights, not the old weights")
current.duration = 0
check(abs((current.effectiveWeight(of: .duration) ?? 0) - 50.0 / 90 * 100) < 0.001,
      "zero duration scores still participate in the weighted score")
let cached = try JSONDecoder().decode(SleepScore.self, from: JSONEncoder().encode(current))
check(cached == current && cached.effectiveWeight(of: .duration) == current.effectiveWeight(of: .duration),
      "offline round trips retain the score policy evidence")
check(cached.appliedDurationCap == 60, "offline round trips retain the reason for the capped score")
let seven = SleepScore(score: 56, duration: 41, inputs: [
    "contributor_policy": 3, "score_total_sleep": 41, "score_rem": 65.56,
    "score_deep": 100, "weight_total_sleep": 40, "weight_rem": 15, "weight_deep": 15,
    "duration_min": 289, "rem_min": 59, "deep_min": 66
], version: "sleep-v3.0")
check(seven.usesContributors && !legacy.usesContributors, "new and cached legacy policies stay distinct")
check(SleepContributor.allCases.count == 7, "all seven factors appear, even when unmeasured")
check(seven.contributorScore(.latency) == nil, "unknown latency is not zero or full marks")
check(abs((seven.contributorWeight(.totalSleep) ?? 0) - 40.0 / 70 * 100) < 0.001,
      "only actually scored contributors receive weight")
check(seven.effectiveWeight(of: .duration) == nil, "new scores never claim legacy group weights")
check(SleepContributor.rating(85) == "OPTIMAL" && SleepContributor.rating(70) == "GOOD" &&
      SleepContributor.rating(60) == "FAIR" && SleepContributor.rating(59) == "PAY ATTENTION",
      "four rating bands match the public reference")
var invalid = seven
invalid.inputs["score_rem"] = .infinity
check(invalid.contributorScore(.rem) == nil, "invalid contributor values are not displayed")
let sevenCached = try JSONDecoder().decode(SleepScore.self, from: JSONEncoder().encode(seven))
check(sevenCached == seven && sevenCached.contributorScore(.rem) == 65.56,
      "new contributor evidence survives offline round trips")
var recordedWindow = seven
recordedWindow.inputs["duration_min"] = 450
recordedWindow.inputs["sleep_elapsed_minutes"] = 480
recordedWindow.inputs["bed_offset"] = 270
let schedule = SleepScheduleNight(day: UserDay(key: "2026-10-20"), score: recordedWindow, summary: nil)
check(schedule.bed == 270 && schedule.wake == 750,
      "cached schedules use elapsed time, not asleep duration, to retain the actual wake time")
if failures > 0 { exit(1) }
"""

with tempfile.TemporaryDirectory(prefix="next-sleep-explanation-") as directory:
    path = Path(directory)
    (path / "main.swift").write_text(source)
    subprocess.run([
        "swiftc", "-swift-version", "5",
        str(APP / "NextBody/Features/Vitals/SleepScoreMath.swift"),
        str(path / "main.swift"), "-o", str(path / "test")
    ], check=True)
    subprocess.run([str(path / "test")], check=True)
    ui_source = "import SwiftUI\n" + model_source + """
enum ScreenMetrics {
    static let size = CGSize(width: 390, height: 844)
}
enum Fmt {
    static let dash = "——"
    static func duration(_ minutes: Int) -> String { "\\(minutes)M" }
}
struct SleepWindowSummary {
    var scores: [SleepScore]
    var slots: [Int]
    var contributorScores: [SleepScore] { scores.filter(\\.usesContributors) }
}
"""
    for name in ["SleepContributorBreakdown", "SleepContributorRow",
                 "SleepContributorCoverage", "SleepContributorWindow"]:
        ui_source += extract(board, f"struct {name}:") + "\n"
    (path / "Views.swift").write_text(ui_source)
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    subprocess.run([
        "swiftc", "-typecheck", "-swift-version", "5", "-sdk", sdk,
        "-target", "arm64-apple-ios17.0-simulator",
        str(APP / "NextBody/DesignSystem/Tokens.swift"),
        str(APP / "NextBody/DesignSystem/Typography.swift"),
        str(APP / "NextBody/Features/Vitals/SleepScoreMath.swift"),
        str(path / "Views.swift")
    ], check=True)
    print("PASS: contributor SwiftUI views typecheck against the iOS SDK and real design tokens")
