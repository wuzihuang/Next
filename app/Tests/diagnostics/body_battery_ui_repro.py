"""Body Battery presentation regression gate using actual Swift declarations.

Run: python3 app/Tests/diagnostics/body_battery_ui_repro.py
Compiles Foundation-only production logic and the refresh/morning handlers with
small UI/transport doubles. No account, Bluetooth or network is used. Source
checks cover removed unsafe writers and wiring that cannot run without SwiftUI;
this does not replace the app build or simulator UI tests.
"""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(relative):
    return (ROOT / relative).read_text()


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


metrics = read("NextBody/Models/Metrics.swift")
store = read("NextBody/Services/DataStore.swift")
detail = read("NextBody/Features/BodyBattery/BodyBatteryDetailView.swift")
morning = read("NextBody/Features/Home/MorningWidget.swift")
profile = read("NextBody/Features/Profile/ProfileView.swift")
panel = read("NextBody/Features/Home/AIPanel.swift")
battery = read("NextBody/Models/BodyBattery.swift")

checks = {
    "refresh uses real sync and never writes a battery score": (
        "OriginDataSync.refreshNow" in declaration(detail, "private func refreshBattery(")
        and "data.today.bodyBattery =" not in detail
        and "BB_TARGET_REANCHORED" not in detail
    ),
    "live callbacks cannot replace only the settled battery hero": (
        "func applyLiveBodyBattery(" not in store and "bodyBatteryPreview ??" not in store
    ),
    "all current readouts apply battery-specific freshness": all(
        "bodyBatteryForDisplay(at:" in source and "TimelineView(" in source
        for source in [detail, profile, panel]
    ),
    "confidence card uses independent battery confidence": (
        "m.bodyBatteryConfidence" in declaration(detail, "private var confidenceCard:")
        and "m.confidence" not in declaration(detail, "private var confidenceCard:")
    ),
    "all charge labels share absolute point bands": all(
        "BodyBattery.chargeWord(" in source for source in [morning, profile, panel]
    ) and "drivers.lastNight / med" not in morning,
    "unreachable FULL forecast is absent": (
        "ChargeForecast" not in battery + panel and "FULL %@" not in battery + panel
    ),
    "wake timestamps are recorded, with no invented 07:12": (
        "07:12" not in detail + profile + morning
        and all("bodyBatteryWakeAt" in source for source in [detail, profile, morning])
    ),
    "day attribution and whole-night charge use separate windows": (
        'L("Recovery since 04:00")' in detail
        and all(".nightCharge" in source for source in [detail, profile, morning, panel])
    ),
    "missing mornings are not labelled as nonwear": (
        'L("DASH · NO MORNING")' in detail
        and "DASH · NOT WORN" not in detail
        and "%d MORNINGS · %d MISSING" in detail
    ),
    "30-day caption includes its partial fifth group": (
        "Five groups cover all 30 days: two days, then four weeks." in detail
        and "Four rolling weeks" not in detail
    ),
    "axis has clock-based positions and no fixed NOW slot": (
        "BodyBatteryCurveMath.fraction(timestamp, in: day)" in detail
        and '["04", "10", "NOW", "22"]' not in detail
        and "/ 86_400" not in detail
    ),
}
for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}", flush=True)

models = "\n".join(declaration(metrics, marker) for marker in [
    "enum Confidence:", "enum BodyBatteryConfidence:", "struct BodyBatteryCoverage:",
    "struct ReserveDrivers:", "struct NightInputs:", "struct ReserveSample:",
])
metric_methods = "\n".join(declaration(metrics, marker) for marker in [
    "var bodyBatteryObservedAt:", "var bodyBatteryWakeAt:", "var bodyBatteryConfidence:",
    "func bodyBatteryFreshness(", "func bodyBatteryForDisplay(",
])
refresh_method = declaration(detail, "private func refreshBattery(").replace("private func", "func", 1)
morning_frame = declaration(morning, "static func frame(")

stubs = r'''
import Foundation
func L(_ format: String, _ args: CVarArg...) -> String { String(format: format, arguments: args) }
enum Fmt {
    static func int(_ value: Int?) -> String { value.map(String.init) ?? "——" }
    static func clock(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}
struct SleepSummary { var wakeAt: Date? }
final class ConsentStore { static let shared = ConsentStore(); var granted = true }
enum BoundBand { static var identifier: String? = "audit-band" }
enum SupabaseClient { static func currentUserIdSnapshot() -> String? { "audit-account" } }
final class LiveSessionStore { static let shared = LiveSessionStore(); var session: String? }
final class BandLiveLifecycle { static let shared = BandLiveLifecycle(); var hasExclusiveOperation = false }
enum LinkState { case connected, disconnected }
final class Band { static let live = Band(); var state = LinkState.connected }
final class Router { enum Takeover { case consent }; var takeover: Takeover? }
enum OriginDataSync {
    static var calls = 0
    static func refreshNow(into: DataStore, minimumInterval: TimeInterval) async { calls += 1 }
}
enum NB { static let lime1 = 1 }
struct PanelWidget {
    enum Kind { case line }; enum Tag { case recover }; enum Target { case bodyBattery }
    enum Data { case series([Double]) }
    var type: Kind; var title: String; var tag: Tag; var sentence: String
    var footer: String; var action: String; var hero: String
    var accentOverride: Int; var targetOverride: Target; var data: Data; var ttlMinutes: Int
}
'''

harness = '''
struct DailyMetrics {
    var day: UserDay
    var bodyBattery: Int? = 45
    var bbWake: Int? = 70
    var targetLoad: Double? = 14.5
    var reserveDrivers: ReserveDrivers?
    var reserveCurve: [ReserveSample] = []
    var sleep: SleepSummary?
    var nightInputs: NightInputs?
    var confidence: Confidence = .pending
''' + metric_methods + '''
}
final class DataStore {
    var today: DailyMetrics
    init(_ today: DailyMetrics) { self.today = today }
}
final class RefreshHarness {
    var data: DataStore
    var router = Router()
    var isRefreshing = false
    var refreshMessage: String?
    init(_ data: DataStore) { self.data = data }
''' + refresh_method + '''
}
enum MorningWidget {
    static let shownKey = "nb.audit.bodyBattery.morningShownDay"
    static var debugNow: Date? { nil }
    static func suppress(_ reason: String) -> PanelWidget? { nil }
''' + morning_frame + '''
}
'''

main = r'''
@main struct Runner {
    static func main() async {
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        let instant = ISO8601DateFormatter().date(from: "2026-09-06T04:00:00Z")!
        let day = UserDay.containing(instant)
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        var m = DailyMetrics(day: day)
        m.reserveCurve = [ReserveSample(ts: instant, value: 45)]
        m.reserveDrivers = ReserveDrivers(lastNight: 50, awake: -8, movement: -12, stress: -5, anchor: 20)
        let data = DataStore(m)
        let refresh = RefreshHarness(data)
        await refresh.refreshBattery()
        check(OriginDataSync.calls == 1 && data.today.bodyBattery == 45 && data.today.bbWake == 70
              && data.today.targetLoad == 14.5 && data.today.reserveCurve.last?.value == 45,
              "refresh requests real evidence without overwriting 45 with wake 70 or altering its target")
        ConsentStore.shared.granted = false
        await refresh.refreshBattery()
        check(OriginDataSync.calls == 1 && refresh.router.takeover == .consent,
              "refresh preserves consent gate")
        ConsentStore.shared.granted = true
        LiveSessionStore.shared.session = "measurement"
        await refresh.refreshBattery()
        check(OriginDataSync.calls == 1, "refresh preserves exclusive measurement gate")
        LiveSessionStore.shared.session = nil

        check(m.bodyBatteryForDisplay(at: instant.addingTimeInterval(89 * 60)) == 45,
              "recent battery remains readable")
        check(m.bodyBatteryFreshness(at: instant.addingTimeInterval(91 * 60)) == .stale,
              "battery dims after 90 minutes independently of live vital updates")
        check(m.bodyBatteryForDisplay(at: instant.addingTimeInterval(7 * 3600)) == nil,
              "seven-hour-old battery becomes unavailable")
        check(m.bodyBatteryFreshness(at: instant.addingTimeInterval(90 * 60)) == .stale,
              "exactly 90 minutes begins stale presentation")
        check(m.bodyBatteryForDisplay(at: instant.addingTimeInterval(6 * 3600)) == nil,
              "exactly six hours begins unavailable presentation")
        check(m.bodyBatteryForDisplay(at: instant.addingTimeInterval(-1)) == nil,
              "a future observation is unavailable rather than fresh")

        let oldArchive = Data(#"{"lastNight":50,"awake":-8,"movement":-12,"stress":-5,"anchor":20,"assumedAnchor":false}"#.utf8)
        let legacy = try! JSONDecoder().decode(ReserveDrivers.self, from: oldArchive)
        check(legacy.nightCharge == nil && legacy.observedAt == nil && legacy.confidence == nil
              && legacy.coverage == nil && legacy.dayCharge == nil && legacy.sum == 25,
              "old reserve archives decode without new fields and preserve the day ledger")
        var complete = legacy
        complete.dayCharge = 30
        complete.nightCharge = 45
        complete.wakeAt = instant.addingTimeInterval(3600)
        complete.observedAt = instant.addingTimeInterval(7200)
        complete.confidence = .medium
        complete.coverage = .init(nightHRV: 0.75, nightRHR: 0.8, dayHeart: 0.9, dayStress: 0.1)
        complete.algoVersion = "bb-2.1"
        let roundTrip = try! JSONDecoder().decode(ReserveDrivers.self, from: JSONEncoder().encode(complete))
        check(roundTrip == complete && roundTrip.sum == 5,
              "new reserve bundle round-trips day/night windows, clocks, confidence, coverage and version")
        m.confidence = .high
        check(m.bodyBatteryConfidence == .low, "composition HIGH cannot promote missing battery confidence")
        m.reserveDrivers?.confidence = .medium
        m.confidence = .pending
        check(m.bodyBatteryConfidence == .medium, "composition PENDING cannot demote battery evidence")
        m.reserveDrivers?.observedAt = instant.addingTimeInterval(-7 * 3600)
        check(m.bodyBatteryForDisplay(at: instant) == nil,
              "real observation timestamp takes precedence over a later curve rendering timestamp")

        check(m.bodyBatteryWakeAt == nil, "no wake timestamp is invented from a curve")
        let wakeAt = instant.addingTimeInterval(8 * 3600 + 39 * 60)
        m.reserveDrivers?.wakeAt = wakeAt
        m.reserveDrivers?.nightCharge = 35
        check(m.bodyBatteryWakeAt == wakeAt, "12:39 wake is preserved despite later daily peaks")
        UserDefaults.standard.removeObject(forKey: MorningWidget.shownKey)
        let frame = MorningWidget.frame(today: m, history: [], now: wakeAt.addingTimeInterval(3600))
        check(frame?.footer == "CHARGED +35 · \(BodyBattery.chargeWord(35))" && frame?.hero == "70",
              "morning uses the same absolute charge label and frozen morning reading")
        check(MorningWidget.frame(today: m, history: [], now: wakeAt.addingTimeInterval(7 * 3600)) == nil,
              "morning window ends six hours after actual wake")
        m.reserveDrivers?.nightCharge = nil
        check(MorningWidget.frame(today: m, history: [], now: wakeAt) == nil,
              "legacy user-day lastNight is never substituted for missing whole-night charge")
        check(Set([0, 20, 32, 45].map(BodyBattery.chargeWord)).count == 4,
              "four absolute charge bands remain distinct without personal-usual assertions")

        let changing = [60, 70, 40, 80].enumerated().map { index, value in
            ReserveSample(ts: instant.addingTimeInterval(Double(index) * 300), value: value)
        }
        let segments = BodyBatteryCurveMath.segments(changing)
        check(segments.map(\.charging) == [true, false, true],
              "later peak cannot recolour an earlier decline")
        let gapped = [changing[0], ReserveSample(ts: instant.addingTimeInterval(3600), value: 80)]
        check(BodyBatteryCurveMath.segments(gapped).isEmpty, "an hour without observations stays a curve gap")
        check(BodyBatteryCurveMath.fraction(day.end, in: day) == 1,
              "the next 04:00 boundary is the chart's right edge")

        let facts = day.rollingBack(30).map {
            BodyBatteryDayFacts(day: $0, wake: 70, now: 60, nightCharge: 30, worn: true, isOpen: false)
        }
        check(BodyBatteryWindowMath.averageWake(facts) == 70
              && BodyBatteryWindowMath.weekRolls(facts).map(\.days) == [2, 7, 7, 7, 7],
              "30 days preserve mean 70 and all five actual groups")
        let partial = [
            BodyBatteryDayFacts(day: day, wake: nil, now: 50, nightCharge: nil, worn: true, isOpen: true),
            BodyBatteryDayFacts(day: day.adding(days: -1), wake: 80, now: 60, nightCharge: 30, worn: true, isOpen: false)
        ]
        check(BodyBatteryWindowMath.averageWake(partial) == 80
              && partial.filter(\.hasWake).count + BodyBatteryWindowMath.emptyCount(partial) == 2,
              "missing morning is excluded from averages even when wrist was worn")

        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        for (iso, expectedHours) in [("2026-03-07T12:00:00Z", 23.0), ("2026-10-31T12:00:00Z", 25.0)] {
            let date = ISO8601DateFormatter().date(from: iso)!
            let dstDay = UserDay.containing(date)
            check(Calendar.current.component(.hour, from: dstDay.end) == 4
                  && dstDay.end.timeIntervalSince(dstDay.start) == expectedHours * 3600
                  && BodyBatteryCurveMath.fraction(dstDay.end, in: dstDay) == 1,
                  "\(Int(expectedHours))-hour DST day ends at local 04:00 and spans exactly one chart")
        }
        exit(failures == 0 ? 0 : 1)
    }
}
'''

with tempfile.TemporaryDirectory(prefix="nextbody-battery-ui-") as directory:
    path = Path(directory)
    source = (
        stubs + models + "\n" + battery
        + read("NextBody/Services/Band/UserDay.swift")
        + read("NextBody/Services/Band/BodyBatteryWindowMath.swift")
        + harness + main
    )
    (path / "audit.swift").write_text(source)
    subprocess.run(["swiftc", "-parse-as-library", str(path / "audit.swift"), "-o", str(path / "audit")], check=True)
    result = subprocess.run([str(path / "audit")]).returncode
    raise SystemExit(result if result else (0 if all(checks.values()) else 1))
