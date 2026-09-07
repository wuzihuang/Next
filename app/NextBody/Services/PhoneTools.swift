import Foundation
import SwiftUI
import UIKit

/// ADR 0018 · phone tools. The model calls them inside a turn; the server suspends the turn
/// and hands the call here; this runs it on the band or in the app and answers with
/// `ok / code / data`, and the turn resumes with that answer. Set an alarm, start a session
/// and log a meal wait for a tap first; sixty seconds without one is CANCELLED.
@MainActor
final class PhoneToolRunner: ObservableObject {
    static let shared = PhoneToolRunner()

    struct Request: Equatable {
        let callID: String
        let name: String
        let args: [String: Any]
        let confirm: Bool
        static func == (a: Request, b: Request) -> Bool { a.callID == b.callID }
        init?(_ raw: [String: Any]) {
            guard let callID = raw["call_id"] as? String, let name = raw["name"] as? String else { return nil }
            self.callID = callID
            self.name = name
            self.args = raw["args"] as? [String: Any] ?? [:]
            self.confirm = raw["confirm"] as? Bool ?? false
        }
    }

    struct Result {
        var ok: Bool
        var code: String
        var data: [String: Any]? = nil
        var message: String? = nil
        static func fail(_ code: String, _ message: String? = nil) -> Result { Result(ok: false, code: code, message: message) }
        static func succeed(_ data: [String: Any]? = nil) -> Result { Result(ok: true, code: "OK", data: data) }
        func payload(callID: String) -> [String: Any] {
            var out: [String: Any] = ["call_id": callID, "ok": ok, "code": code]
            if let data { out["data"] = data }
            if let message { out["message"] = String(message.prefix(200)) }
            return out
        }
    }

    /// What the screen asks before a tool with a side effect runs. RootView presents it.
    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let resolve: (Bool) -> Void
    }
    @Published var confirmation: Confirmation?
    /// The tool that is running right now, for the thinking stream's foot.
    @Published private(set) var running: String?

    static let confirmSeconds: TimeInterval = 60
    static let flowSeconds: TimeInterval = 5 * 60

    weak var router: Router?
    /// Alarms as last read from the band, so a turn can cite them without a BLE round trip.
    private(set) var cachedAlarms: [BandAlarm] = []
    private(set) var alarmsReadAt: Date?

    /// The band as the phone sees it now, sent with every turn as read evidence.
    func deviceState(store: DataStore) -> [String: Any] {
        let band = store.band
        let iso = ISO8601DateFormatter()
        var out: [String: Any] = [
            "connected": Band.live.state == .connected,
            "battery_percent": band.batteryPercent.map { $0 as Any } ?? NSNull(),
            "charging": (band.displayedCharge == .charging) as Any,
            "last_sync_at": band.connected ? iso.string(from: band.lastSync) : NSNull(),
            "app_foreground": UIApplication.shared.applicationState == .active,
        ]
        if alarmsReadAt != nil {
            out["alarms"] = Array(cachedAlarms.prefix(10)).map(Self.alarmJSON)
        }
        return out
    }

    func run(_ request: Request, store: DataStore) async -> Result {
        running = request.name
        defer { running = nil }
        guard UIApplication.shared.applicationState != .background else { return .fail("APP_BACKGROUND") }
        if request.confirm {
            guard await confirm(request) else { return .fail("CANCELLED", L("Not confirmed.")) }
        }
        switch request.name {
        case "device.find":          return await findBand()
        case "device.sync":          return await syncBand(store: store)
        case "device.alarm.set":     return await setAlarm(request.args)
        case "device.alarm.delete":  return await deleteAlarm(request.args)
        case "sport.start":          return await startSport(request.args, store: store)
        case "sport.stop":           return await stopSport()
        case "meal.log":             return logMeal(request.args, store: store)
        case "balance_check.start":  return await runFlow(.measure(.ecg))
        case "body_scan.start":      return await runFlow(.measure(.bodyComposition))
        case "app.open":             return openPage(request.args)
        default:                     return .fail("UNKNOWN_TOOL")
        }
    }

    // MARK: confirmation

    private func confirm(_ request: Request) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var settled = false
            let resolve: (Bool) -> Void = { [weak self] yes in
                guard !settled else { return }
                settled = true
                self?.confirmation = nil
                continuation.resume(returning: yes)
            }
            confirmation = Confirmation(title: Self.confirmTitle(request), detail: Self.confirmDetail(request), resolve: resolve)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.confirmSeconds))
                resolve(false)
            }
        }
    }

    private static func confirmTitle(_ r: Request) -> String {
        switch r.name {
        case "device.alarm.set":    return L("Set this alarm on the band?")
        case "device.alarm.delete": return L("Delete this alarm?")
        case "sport.start":         return L("Start a session?")
        case "sport.stop":          return L("Stop the session?")
        case "meal.log":            return L("Log this meal?")
        default:                    return L("Continue?")
        }
    }

    private static func confirmDetail(_ r: Request) -> String {
        switch r.name {
        case "device.alarm.set":
            let time = r.args["time"] as? String ?? "--:--"
            let days = (r.args["days"] as? [Int]) ?? []
            let when = days.isEmpty ? L("once") : days.sorted().map { Self.dayName($0) }.joined(separator: " ")
            return "\(time) · \(when)"
        case "device.alarm.delete":
            return L("Alarm %@", r.args["alarm_id"] as? String ?? "?")
        case "sport.start":
            return L(Self.sportMode(for: r.args["sport"] as? String).name)
        case "meal.log":
            let draft = r.args["draft"] as? [String: Any] ?? [:]
            let kcal = (draft["kcal"] as? Double) ?? (draft["kcal"] as? Int).map(Double.init) ?? 0
            return "\(draft["name"] as? String ?? "") · \(Fmt.kcal(kcal)) KCAL"
        default:
            return ""
        }
    }

    private static func dayName(_ d: Int) -> String {
        ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][max(0, min(6, d))]
    }

    // MARK: band

    private func bandReady() -> Result? {
        guard BoundBand.identifier != nil else { return .fail("BAND_DISCONNECTED", L("No band is paired.")) }
        guard Band.live.state == .connected else { return .fail("BAND_DISCONNECTED", L("The band is not connected.")) }
        return nil
    }

    private func findBand() async -> Result {
        if let blocked = bandReady() { return blocked }
        do {
            try await Band.live.startFindHoop()
            try? await Task.sleep(for: .seconds(4))
            await Band.live.stopFindHoop()
            return .succeed(["vibrated": true])
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    private func syncBand(store: DataStore) async -> Result {
        if let blocked = bandReady() { return blocked }
        await Band.live.prepareFreshSync()
        let points = await OriginDataSync().sync(day: store.today.day, into: store)
        let iso = ISO8601DateFormatter()
        return .succeed(["points": points, "synced_at": iso.string(from: Date())])
    }

    private func setAlarm(_ args: [String: Any]) async -> Result {
        if let blocked = bandReady() { return blocked }
        guard let time = args["time"] as? String, let (hour, minute) = Self.parseTime(time) else { return .fail("BAND_ERROR", L("Invalid time.")) }
        do {
            let alarms = try await Band.live.readAlarms()
            guard let id = BandAlarmMath.nextID(in: alarms) else { return .fail("ALARM_SLOTS_FULL") }
            let days = (args["days"] as? [Int]) ?? []
            let draft = BandAlarm(id: id, hour: hour, minute: minute, on: true,
                                  repeatMask: Self.repeatMask(days: days), date: BandAlarm.onceDatePlaceholder,
                                  scene: BandAlarm.silentScene, text: String((args["label"] as? String ?? "").prefix(20)))
            let after = try await Band.live.writeAlarm(BandAlarmMath.prepared(draft))
            remember(after)
            return .succeed(["alarm_id": String(id), "alarms": after.map(Self.alarmJSON)])
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    private func deleteAlarm(_ args: [String: Any]) async -> Result {
        if let blocked = bandReady() { return blocked }
        guard let raw = args["alarm_id"] as? String, let id = Int(raw) else { return .fail("ALARM_NOT_FOUND") }
        do {
            let alarms = try await Band.live.readAlarms()
            guard let alarm = alarms.first(where: { $0.id == id }) else { remember(alarms); return .fail("ALARM_NOT_FOUND") }
            let after = try await Band.live.deleteAlarm(alarm)
            remember(after)
            return .succeed(["alarms": after.map(Self.alarmJSON)])
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    func remember(_ alarms: [BandAlarm]) {
        cachedAlarms = alarms
        alarmsReadAt = Date()
    }

    private static func alarmJSON(_ a: BandAlarm) -> [String: Any] {
        [
            "id": String(a.id),
            "time": String(format: "%02d:%02d", a.hour, a.minute),
            "days": days(mask: a.repeatMask),
            "enabled": a.on,
            "label": a.text,
        ]
    }

    /// Band mask is LSB = Monday … bit 6 = Sunday; the wire uses 0 = Sunday … 6 = Saturday.
    private static func repeatMask(days: [Int]) -> Int {
        var mask = 0
        for d in days {
            let bit = d == 0 ? 6 : d - 1
            if (0...6).contains(bit) { mask |= 1 << bit }
        }
        return mask
    }

    private static func days(mask: Int) -> [Int] {
        (0...6).filter { mask & (1 << $0) != 0 }.map { $0 == 6 ? 0 : $0 + 1 }
    }

    private static func parseTime(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func code(_ error: Error) -> String {
        if let band = error as? BandError {
            switch band {
            case .notConnected: return "BAND_DISCONNECTED"
            case .unsupported:  return "UNSUPPORTED"
            case .timeout:      return "TIMEOUT"
            default:            return "BAND_ERROR"
            }
        }
        return "BAND_ERROR"
    }

    // MARK: sport

    private static func sportMode(for sport: String?) -> SportModeOption {
        let name: String
        switch sport {
        case "run":      name = "Outdoor run"
        case "walk":     name = "Outdoor walk"
        case "ride":     name = "Outdoor cycle"
        case "strength": name = "Common"
        default:         name = "Common"
        }
        return SportModeCatalog.modes.first { $0.name == name } ?? SportModeCatalog.modes[0]
    }

    private func startSport(_ args: [String: Any], store: DataStore) async -> Result {
        if let blocked = bandReady() { return blocked }
        let live = LiveSessionStore.shared
        guard live.session == nil else { return .fail("SESSION_ACTIVE") }
        let mode = Self.sportMode(for: args["sport"] as? String)
        live.begin(mode, profile: store.profile, weightKg: store.today.weightKg ?? store.weighIns.first?.weightKg)
        try? await Task.sleep(for: .milliseconds(600))
        if let refusal = live.refusal { return .fail("BAND_ERROR", refusal) }
        guard live.session != nil else { return .fail("BAND_ERROR", live.errorLine) }
        return .succeed(["mode": mode.name])
    }

    private func stopSport() async -> Result {
        let live = LiveSessionStore.shared
        guard live.session != nil else { return .fail("NO_SESSION") }
        let widget = await live.stop()
        return .succeed(["summary": widget?.sentence ?? ""])
    }

    // MARK: meal

    private func logMeal(_ args: [String: Any], store: DataStore) -> Result {
        guard let draft = args["draft"] as? [String: Any] else { return .fail("ESTIMATE_REQUIRED") }
        let slotRaw = args["slot"] as? String
        let slot = slotRaw.flatMap(MealEntry.Slot.init(rawValue:)) ?? MealEntry.Slot.guess(at: Date(), day: store.today.day)
        do {
            let logged = try AIService.shared.logMealDraft(draft, slot: slot, day: store.today.day, into: store)
            return .succeed(["meal_id": logged.id.uuidString.lowercased(), "kcal": logged.kcal, "slot": slot.rawValue])
        } catch {
            let text = error.localizedDescription
            return .fail(text.contains("fasted") ? "FASTED_DAY" : "BAND_ERROR", text)
        }
    }

    // MARK: flows and pages

    private func runFlow(_ takeover: Takeover) async -> Result {
        guard let router else { return .fail("APP_BACKGROUND") }
        if case .measure = takeover, let blocked = bandReady() { return blocked }
        let before = router.measuredWidget?.id
        router.takeover = takeover
        let deadline = Date().addingTimeInterval(Self.flowSeconds)
        // Give the takeover a beat to mount before watching for it to fold.
        try? await Task.sleep(for: .milliseconds(500))
        while router.takeover != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(400))
        }
        if router.takeover != nil { router.takeover = nil; return .fail("TIMEOUT") }
        let completed = router.measuredWidget?.id != before && router.measuredWidget != nil
        return completed
            ? .succeed(["completed": true, "summary": router.measuredWidget?.sentence ?? ""])
            : .fail("ABANDONED", L("The check was closed before it finished."))
    }

    private func openPage(_ args: [String: Any]) -> Result {
        guard let router else { return .fail("APP_BACKGROUND") }
        let page = args["page"] as? String ?? ""
        switch page {
        case "plan":   router.requestPlan()
        case "device": router.open(.device, from: .profile)
        case "sleep":  router.open(.vitals(.sleep))
        case "heart":  router.open(.vitals(.heart))
        default:
            guard let destination = Destination(envelopeTarget: page) else { return .fail("BAND_ERROR", L("Unknown page.")) }
            router.open(destination)
        }
        return .succeed(["page": page])
    }
}
