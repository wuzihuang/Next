import Foundation
import SwiftUI
import UIKit
import Combine

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

    typealias Confirmation = PhoneToolExecution.Prompt
    @Published private(set) var confirmation: Confirmation?
    @Published private(set) var running: String?
    static let flowSeconds: TimeInterval = 5 * 60

    private var activeTurn = UUID()
    private var observations: Set<AnyCancellable> = []
    private lazy var execution = PhoneToolExecution(current: { [unowned self] in
        .init(scope: currentScope, consent: ConsentStore.shared.granted,
              foreground: UIApplication.shared.applicationState == .active)
    }, sleep: { try await Task.sleep(for: .seconds($0)) }, changed: { [weak self] confirmation, running in
        self?.confirmation = confirmation
        self?.running = running
    })

    private init() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidateTurn(.background) }
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: SupabaseClient.requestSessionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.execution.refreshEligibility() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.execution.refreshEligibility() }
            .store(in: &observations)
        ConsentStore.shared.$choice.sink { [weak self] choice in
            if choice != .granted { self?.invalidateTurn(.consentRequired) }
        }.store(in: &observations)
    }

    private var currentScope: PhoneToolExecution.Scope {
        .init(session: SupabaseClient.currentRequestSessionSnapshot(), turnID: activeTurn,
              binding: BoundBand.identifier)
    }

    private func invalidateTurn(_ reason: PhoneToolExecution.Failure) {
        activeTurn = UUID()
        execution.invalidateAll(reason)
    }

    func beginTurn(_ id: UUID) -> PhoneToolExecution.Scope {
        activeTurn = id
        execution.refreshEligibility()
        return currentScope
    }

    func finishTurn(_ id: UUID) {
        guard activeTurn == id else { return }
        activeTurn = UUID()
        execution.refreshEligibility()
    }

    func resolveConfirmation(id: UUID, approved: Bool) {
        execution.resolve(id: id, approved: approved)
    }

    private var measurementOwner: (generation: UInt, execution: PhoneToolExecution.Execution)?
    var measurementExecution: PhoneToolExecution.Execution? {
        guard let owner = measurementOwner, router?.takeoverGeneration == owner.generation else { return nil }
        return owner.execution
    }
    weak var router: Router?
    /// Alarms as last read from the band, so a turn can cite them without a BLE round trip.
    private(set) var cachedAlarms: [BandAlarm] = []
    private(set) var alarmsReadAt: Date?
    private var alarmsOwner: (session: RequestSession, binding: String?)?
    private var findOwner: UUID?

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
        if alarmsReadAt != nil, alarmsOwner?.session == SupabaseClient.currentRequestSessionSnapshot(),
           alarmsOwner?.binding == BoundBand.identifier {
            out["alarms"] = Array(cachedAlarms.prefix(10)).map(Self.alarmJSON)
        }
        return out
    }

    func run(_ request: Request, scope: PhoneToolExecution.Scope, store: DataStore) async -> Result {
        do {
            return try await execution.run(scope: scope, callID: request.callID, name: request.name,
                confirmation: request.confirm ? (Self.confirmTitle(request), Self.confirmDetail(request)) : nil) { permit in
                switch request.name {
                case "device.find":          return await findBand(permit)
                case "device.sync":          return await syncBand(store: store, permit: permit)
                case "device.alarm.set":     return await setAlarm(request.args, permit: permit)
                case "device.alarm.delete":  return await deleteAlarm(request.args, permit: permit)
                case "sport.start":          return await startSport(request.args, store: store, permit: permit)
                case "sport.stop":           return await stopSport(permit)
                case "meal.log":             return try logMeal(request.args, store: store, permit: permit)
                case "balance_check.start":  return await runFlow(.measure(.ecg), permit: permit)
                case "body_scan.start":      return await runFlow(.measure(.bodyComposition), permit: permit)
                case "app.open":             return try openPage(request.args, permit: permit)
                default:                     return .fail("UNKNOWN_TOOL")
                }
            }
        } catch { return .fail(Self.code(error), error.localizedDescription) }
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

    private func findBand(_ permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        findOwner = permit.id
        let result: Result
        do {
            try await permit.perform { try await Band.live.startFindHoop() }
            try await Task.sleep(for: .seconds(4))
            try permit.check()
            result = .succeed(["vibrated": true])
        } catch { result = .fail(Self.code(error), error.localizedDescription) }
        // Stopping the find we already issued is cleanup. It must never stop a successor
        // request or send a command to the band/account that replaced this one.
        if findOwner == permit.id,
           SupabaseClient.currentRequestSessionSnapshot() == permit.scope.session,
           BoundBand.identifier == permit.scope.binding {
            await Band.live.stopFindHoop()
        }
        if findOwner == permit.id { findOwner = nil }
        return result
    }

    private func syncBand(store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        do {
            let result = try await permit.perform {
                await OriginDataSync.refreshNow(into: store, request: .phoneTool)
            }
            guard result.status == .success, let at = result.syncedAt else {
                let code: String
                switch result.status {
                case .unbound, .disconnected: code = "BAND_DISCONNECTED"
                case .consentRequired: code = "CONSENT_REQUIRED"
                case .signedOut: code = "SESSION_CHANGED"
                case .cancelled: code = "CANCELLED"
                case .busy, .throttled: code = "BUSY"
                case .partial: code = "SYNC_PARTIAL"
                default: code = "BAND_ERROR"
                }
                return .fail(code)
            }
            return .succeed(["points": result.points, "synced_at": ISO8601DateFormatter().string(from: at)])
        } catch { return .fail(Self.code(error), error.localizedDescription) }
    }

    private func setAlarm(_ args: [String: Any], permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        guard let time = args["time"] as? String, let (hour, minute) = Self.parseTime(time) else { return .fail("BAND_ERROR", L("Invalid time.")) }
        do {
            let days = (args["days"] as? [Int]) ?? []
            let draft = BandAlarm(id: 0, hour: hour, minute: minute, on: true,
                                  repeatMask: Self.repeatMask(days: days), date: BandAlarm.onceDatePlaceholder,
                                  scene: BandAlarm.silentScene, text: String((args["label"] as? String ?? "").prefix(20)))
            let result = try await permit.setAlarm(draft, read: { try await Band.live.readAlarms() },
                                                   write: { try await Band.live.writeAlarm($0) })
            remember(result.alarms)
            return .succeed(["alarm_id": String(result.id), "alarms": result.alarms.map(Self.alarmJSON)])
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    private func deleteAlarm(_ args: [String: Any], permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        guard let raw = args["alarm_id"] as? String, let id = Int(raw) else { return .fail("ALARM_NOT_FOUND") }
        do {
            let after = try await permit.deleteAlarm(id, read: { try await Band.live.readAlarms() },
                                                    delete: { try await Band.live.deleteAlarm($0) })
            remember(after)
            return .succeed(["alarms": after.map(Self.alarmJSON)])
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    func remember(_ alarms: [BandAlarm]) {
        cachedAlarms = alarms
        alarmsReadAt = Date()
        alarmsOwner = (SupabaseClient.currentRequestSessionSnapshot(), BoundBand.identifier)
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
        if let execution = error as? PhoneToolExecution.Failure { return execution.rawValue }
        if error is CancellationError { return "CANCELLED" }
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

    private func startSport(_ args: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        let live = LiveSessionStore.shared
        guard live.session == nil else { return .fail("SESSION_ACTIVE") }
        let mode = Self.sportMode(for: args["sport"] as? String)
        do {
            try permit.check()
            live.begin(mode, profile: store.profile, weightKg: store.today.weightKg ?? store.weighIns.first?.weightKg,
                       authorized: { permit.isAuthorized })
            try await permit.perform { await live.awaitOpening(authorized: { permit.isAuthorized }) }
        } catch { return .fail(Self.code(error), error.localizedDescription) }
        if let refusal = live.refusal { return .fail("BAND_ERROR", refusal) }
        guard live.session != nil else { return .fail("BAND_ERROR", live.errorLine) }
        return .succeed(["mode": mode.name])
    }

    private func stopSport(_ permit: PhoneToolExecution.Execution) async -> Result {
        let live = LiveSessionStore.shared
        guard live.session != nil else { return .fail("NO_SESSION") }
        do {
            let widget = try await permit.perform { await live.stop(authorized: { permit.isAuthorized }) }
            return .succeed(["summary": widget?.sentence ?? ""])
        } catch { return .fail(Self.code(error), error.localizedDescription) }
    }

    // MARK: meal

    private func logMeal(_ args: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) throws -> Result {
        try permit.check()
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

    private func runFlow(_ takeover: Takeover, permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let router else { return .fail("APP_BACKGROUND") }
        if case .measure = takeover, let blocked = bandReady() { return blocked }
        let before = router.measuredWidget?.id
        guard router.takeover == nil else { return .fail("BUSY") }
        router.takeover = takeover
        let generation = router.takeoverGeneration
        measurementOwner = (generation, permit)
        defer {
            BandMeasurementLifetime.shared.cancel(id: permit.id)
            if router.takeoverGeneration == generation { router.takeover = nil }
            if measurementOwner?.execution === permit { measurementOwner = nil }
        }
        let deadline = Date().addingTimeInterval(Self.flowSeconds)
        // Give the takeover a beat to mount before watching for it to fold.
        try? await Task.sleep(for: .milliseconds(500))
        while router.takeoverGeneration == generation, router.takeover == takeover, Date() < deadline {
            guard permit.isAuthorized else { return .fail("CANCELLED") }
            try? await Task.sleep(for: .milliseconds(400))
        }
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        if router.takeoverGeneration == generation { return .fail("TIMEOUT") }
        guard router.takeover == nil, router.takeoverGeneration == generation &+ 1 else { return .fail("ABANDONED") }
        let completed = router.measuredWidget?.id != before && router.measuredWidget != nil
        return completed
            ? .succeed(["completed": true, "summary": router.measuredWidget?.sentence ?? ""])
            : .fail("ABANDONED", L("The check was closed before it finished."))
    }

    private func openPage(_ args: [String: Any], permit: PhoneToolExecution.Execution) throws -> Result {
        try permit.check()
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
