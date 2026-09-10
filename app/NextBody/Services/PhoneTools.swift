import Foundation
import SwiftUI
import UIKit
import Combine
import os

/// ADR 0018 · phone tools. The model calls them inside a turn; the server suspends the turn
/// and hands the call here; this runs it on the band or in the app and answers with
/// `ok / code / data`, and the turn resumes with that answer.
///
/// docs/plans/2026-09-09-ai-tool-surface.md · three tools reach the phone now:
///   `write {entity, op, id, fields}` — every record and setting the app can change,
///   `do {action, …}`                 — verbs and navigation,
///   `health.prepare`                 — the upload-before-read handshake.
/// The server has already normalized the arguments and resolved a `match` into an id; the
/// `confirm` flag is fixed per (entity, op) on the server and never chosen by the model.
/// Sixty seconds without a tap is CANCELLED. Every write pushes its inverse onto an undo
/// stack so `do undo` can take it back within the session.
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

    /// What Home lends the runner: the panel is Home's own state, so the runner asks Home
    /// to confirm the draft, clear the widget or refresh the advice rather than reaching in.
    struct PanelHandler {
        var confirmDraft: () -> Result
        var dismiss: () -> Bool
        var refreshPlan: () -> Bool
        var screen: () -> [String: Any]?
    }
    var panelHandler: PanelHandler?

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
        #if DEBUG
        os.Logger(subsystem: "com.nextbody.hoop", category: "phone-tool")
            .notice("NB phone · prompt=\(confirmation?.title ?? "-", privacy: .public) running=\(running ?? "-", privacy: .public) fg=\(UIApplication.shared.applicationState == .active, privacy: .public) takeover=\(String(describing: self?.router?.takeover), privacy: .public) sheet=\(String(describing: self?.router?.sheet), privacy: .public)")
        #endif
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
    /// Auto-measurement slots as last read, for `find band_setting` without a round trip.
    private(set) var cachedSlots: [AutoMonitorSlot] = []
    private var slotsOwner: String?
    private var hrAlarm: (on: Bool, low: Int, high: Int)?
    private var findOwner: UUID?

    /// One reversible step. The stack is per app session and per account.
    private struct Undo {
        let label: String
        let perform: @MainActor (PhoneToolExecution.Execution, DataStore) async -> Result
    }
    private var undoStack: [Undo] = []
    private var undoOwner: String?
    private func pushUndo(_ label: String, _ perform: @escaping @MainActor (PhoneToolExecution.Execution, DataStore) async -> Result) {
        let owner = SupabaseClient.currentUserIdSnapshot()
        if undoOwner != owner { undoStack.removeAll(); undoOwner = owner }
        undoStack.append(Undo(label: label, perform: perform))
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    /// The band and the phone as the turn sees them now: read evidence, sent with every turn.
    /// `settings` is what `find` answers from for phone-held state.
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
        } else {
            primeAlarmsIfNeeded()
        }
        let prefs = NotificationReach.Prefs.current
        var settings: [String: Any] = [
            "notifications": ["morning": prefs.morning, "training": prefs.training, "meals": prefs.meals,
                              "wrap": prefs.wrap, "energy": prefs.energy, "band": prefs.band, "quiet": prefs.quiet],
            "haptics": HapticsSetting.shared.enabled,
            "sync_cadence": SyncCadence.minutes,
            "chat_sessions": Array(ChatStore.shared.sessions.prefix(10)).map {
                ["id": $0.id, "title": $0.title, "updated_at": iso.string(from: $0.updatedAt)]
            },
        ]
        if slotsOwner == BoundBand.identifier, !cachedSlots.isEmpty {
            settings["auto_monitor"] = cachedSlots.map(Self.slotJSON)
        }
        if let hrAlarm { settings["hr_alarm"] = ["on": hrAlarm.on, "low": hrAlarm.low, "high": hrAlarm.high] }
        if let screen = panelHandler?.screen() { settings["screen"] = screen }
        out["settings"] = settings
        return out
    }

    func run(_ request: Request, scope: PhoneToolExecution.Scope, store: DataStore) async -> Result {
        let result = await runLogged(request, scope: scope, store: store)
        #if DEBUG
        os.Logger(subsystem: "com.nextbody.hoop", category: "phone-tool")
            .notice("NB phone · \(request.name, privacy: .public) \(request.args["entity"] as? String ?? request.args["action"] as? String ?? "", privacy: .public) confirm=\(request.confirm, privacy: .public) → \(result.code, privacy: .public) \(result.message ?? "", privacy: .public)")
        #endif
        return result
    }

    private func runLogged(_ request: Request, scope: PhoneToolExecution.Scope, store: DataStore) async -> Result {
        do {
            return try await execution.run(scope: scope, callID: request.callID, name: request.name,
                confirmation: request.confirm ? (Self.confirmTitle(request), Self.confirmDetail(request)) : nil) { permit in
                switch request.name {
                case "health.prepare":
                    guard let owner = permit.scope.session.owner else { return .fail("SESSION_CHANGED") }
                    let freshness = try await permit.perform {
                        await AIService.shared.prepareFreshness(day: store.today.day, owner: owner,
                            isAuthorized: { permit.isAuthorized })
                    }
                    return .succeed(freshness)
                case "write": return await runWrite(request.args, store: store, permit: permit)
                case "do":    return await runDo(request.args, store: store, permit: permit)
                default:      return .fail("UNKNOWN_TOOL")
                }
            }
        } catch { return .fail(Self.code(error), Self.message(error)) }
    }

    /// An execution failure's code says it all; its localizedDescription is an enum dump.
    private static func message(_ error: Error) -> String? {
        error is PhoneToolExecution.Failure || error is CancellationError ? nil : error.localizedDescription
    }

    // MARK: confirm copy

    private static func confirmTitle(_ r: Request) -> String {
        let entity = r.args["entity"] as? String ?? ""
        let op = r.args["op"] as? String ?? ""
        let action = r.args["action"] as? String ?? ""
        switch (r.name, entity, op, action) {
        case ("write", "meal", "create", _):   return L("Log this meal?")
        case ("write", "meal", "update", _):   return L("Change this meal?")
        case ("write", "meal", "delete", _):   return L("Delete this meal?")
        case ("write", "day", _, _):           return L("Mark today as fasted?")
        case ("write", "weigh_in", "create", _): return L("Save this weigh-in?")
        case ("write", "weigh_in", "delete", _): return L("Delete this weigh-in?")
        case ("write", "alarm", "create", _):  return L("Set this alarm on the band?")
        case ("write", "alarm", "update", _):  return L("Change this alarm?")
        case ("write", "alarm", "delete", _):  return L("Delete this alarm?")
        case ("write", "sleep_night", _, _):
            return (r.args["fields"] as? [String: Any])?["clear"] as? Bool == true
                ? L("Undo the sleep correction?") : L("Correct this night's sleep times?")
        case ("write", "band_setting", _, _):  return L("Change this band setting?")
        case ("write", "hr_alarm", _, _):      return L("Change the heart-rate alarm?")
        case ("write", "profile", _, _):       return L("Change your profile?")
        case ("write", "memory", _, _):        return L("Clear the AI memory?")
        case ("write", "chat_session", _, _):  return L("Delete chat history?")
        case ("do", _, _, "sport.start"):      return L("Start a session?")
        case ("do", _, _, "sport.stop"):       return L("Stop the session?")
        case ("do", _, _, "panel.confirm"):    return L("Log this meal?")
        default:                               return L("Continue?")
        }
    }

    private static func confirmDetail(_ r: Request) -> String {
        let fields = r.args["fields"] as? [String: Any] ?? [:]
        if let label = r.args["label"] as? String, !label.isEmpty {
            let change = fields.sorted { $0.key < $1.key }.map { "\(Self.fieldWord($0.key)) \(Self.valueWord($0.value))" }.joined(separator: " · ")
            return r.args["op"] as? String == "update" && !change.isEmpty ? "\(label)\n→ \(change)" : label
        }
        switch (r.args["entity"] as? String ?? "", r.args["action"] as? String ?? "") {
        case ("meal", _):
            if let draft = r.args["draft"] as? [String: Any] {
                let kcal = (draft["kcal"] as? Double) ?? (draft["kcal"] as? Int).map(Double.init) ?? 0
                return "\(draft["name"] as? String ?? "") · \(Fmt.kcal(kcal)) KCAL"
            }
            return fields.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
        case ("alarm", _):
            let time = fields["time"] as? String ?? "--:--"
            let days = (fields["days"] as? [Int]) ?? []
            let when = days.isEmpty ? L("once") : days.sorted().map { Self.dayName($0) }.joined(separator: " ")
            return "\(time) · \(when)"
        case ("weigh_in", _):
            return "\(fields["weight_kg"] ?? "?") KG"
        case ("sleep_night", _):
            let day = fields["day"] as? String ?? ""
            if fields["clear"] as? Bool == true { return day }
            return "\(day)\n\(fields["start"] as? String ?? "--:--") → \(fields["end"] as? String ?? "--:--")"
        case ("band_setting", _), ("hr_alarm", _), ("profile", _):
            return fields.sorted { $0.key < $1.key }.map { "\(Self.fieldWord($0.key)) \(Self.valueWord($0.value))" }.joined(separator: " · ")
        case (_, "sport.start"):
            return L(Self.sportMode(named: r.args["mode"] as? String).name)
        case (_, "panel.confirm"):
            return PhoneToolRunner.shared.panelHandler?.screen()?["draft"] as? String ?? ""
        default:
            return ""
        }
    }

    private static func fieldWord(_ key: String) -> String {
        switch key {
        case "slot": return L("slot")
        case "at": return L("time")
        case "name": return L("name")
        case "kcal": return "KCAL"
        case "enabled", "on": return L("enabled")
        case "days": return L("days")
        case "interval_min": return L("every")
        case "slot": return L("measure")
        case "high": return L("upper")
        case "low": return L("lower")
        case "goal": return L("goal")
        case "units": return L("units")
        case "language": return L("language")
        case "height_cm": return L("height")
        case "minutes": return L("every")
        default: return key
        }
    }

    private static func valueWord(_ value: Any) -> String {
        if let s = value as? String, let slot = MealEntry.Slot(rawValue: s) { return L(slot.rawValue.capitalized) }
        if let b = value as? Bool { return b ? L("on") : L("off") }
        if let s = value as? String, let kind = AutoMonitorSlot.Kind(rawValue: s) { return L(Self.slotName(kind)) }
        if let s = value as? String, ["CUT", "RECOMP", "BULK"].contains(s) { return L(s) }
        if let days = value as? [Int] { return days.isEmpty ? L("once") : days.sorted().map { dayName($0) }.joined(separator: " ") }
        return "\(value)"
    }

    private static func slotName(_ k: AutoMonitorSlot.Kind) -> String {
        switch k {
        case .heartRate: return "Heart rate"
        case .bloodPressure: return "Blood pressure"
        case .bloodGlucose: return "Meal response"
        case .stress: return "Stress"
        case .bloodOxygen: return "Blood oxygen"
        case .temperature: return "Temperature"
        case .lorentz: return "Lorentz"
        case .hrv: return "HRV"
        case .scientificSleep: return "Sleep"
        case .bloodComponents: return "Blood components"
        }
    }

    private static func dayName(_ d: Int) -> String {
        ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][max(0, min(6, d))]
    }

    // MARK: write

    private func runWrite(_ args: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        let entity = args["entity"] as? String ?? ""
        let op = args["op"] as? String ?? ""
        let id = args["id"] as? String
        let fields = args["fields"] as? [String: Any] ?? [:]
        switch entity {
        case "meal":         return await writeMeal(op, id: id, fields: fields, draft: args["draft"] as? [String: Any], store: store, permit: permit)
        case "day":          return await markFasted(store: store, permit: permit)
        case "weigh_in":     return await writeWeighIn(op, id: id, fields: fields, store: store, permit: permit)
        case "sleep_night":  return await writeSleepNight(fields, store: store, permit: permit)
        case "alarm":        return await writeAlarm(op, id: id, match: args["match"] as? [String: Any] ?? [:], fields: fields, permit: permit)
        case "band_setting": return await writeBandSetting(fields, permit: permit)
        case "hr_alarm":     return await writeHeartRateAlarm(fields, permit: permit)
        case "sync_cadence": return writeCadence(fields, permit: permit)
        case "profile":      return await writeProfile(fields, store: store, permit: permit)
        case "notification": return writeNotification(fields, permit: permit)
        case "haptics":      return writeHaptics(fields, permit: permit)
        case "screen":       return dismissScreen(permit)
        case "chat_session": return writeChatSession(op, id: id, fields: fields, permit: permit)
        default:             return .fail("UNSUPPORTED", L("The phone cannot change %@.", entity))
        }
    }

    // MARK: meal

    private func mealEntry(_ id: String?, store: DataStore) -> MealEntry? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return store.meals.first(where: { $0.id == uuid }) ?? store.recentMeals.first(where: { $0.id == uuid })
    }

    private static func day(from key: Any?, fallback: UserDay) -> UserDay {
        guard let key = key as? String else { return fallback }
        let f = DateFormatter(); f.calendar = .current; f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return fallback }
        return UserDay.containing(date.addingTimeInterval(12 * 3600))
    }

    private static func clock(_ hhmm: Any?, on day: UserDay, fallback: Date) -> Date {
        guard let s = hhmm as? String, let (h, m) = parseTime(s) else { return fallback }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day.date.addingTimeInterval(12 * 3600)) ?? fallback
    }

    private func mealJSON(_ m: MealEntry) -> [String: Any] {
        ["id": m.id.uuidString.lowercased(), "day": m.day.key, "slot": m.slot.rawValue, "name": m.text,
         "kcal": m.kcal, "protein_g": m.protein, "carb_g": m.carb, "fat_g": m.fat,
         "at": ISO8601DateFormatter().string(from: m.at)]
    }

    private func writeMeal(_ op: String, id: String?, fields: [String: Any], draft: [String: Any]?,
                           store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        switch op {
        case "create":
            let day = Self.day(from: fields["day"], fallback: store.today.day)
            let slot = (fields["slot"] as? String).flatMap(MealEntry.Slot.init(rawValue:))
                ?? MealEntry.Slot.guess(at: Self.clock(fields["at"], on: day, fallback: Date()), day: day)
            var output: [String: Any]
            if let draft { output = draft }
            else {
                guard let name = fields["name"] as? String, let kcal = fields["kcal"] as? Double ?? (fields["kcal"] as? Int).map(Double.init) else {
                    return .fail("ESTIMATE_REQUIRED")
                }
                output = ["name": name, "kcal": Int(kcal), "protein_g": fields["protein_g"] ?? 0, "carb_g": fields["carb_g"] ?? 0,
                          "fat_g": fields["fat_g"] ?? 0, "confidence": "HIGH", "model_version": "voice-entry-v1", "source": "typed"]
            }
            do {
                let logged = try AIService.shared.logMealDraft(output, slot: slot, day: day, into: store)
                let mealID = logged.id
                if let owner = SupabaseClient.currentUserIdSnapshot(), let rejected = await settleMealOutbox(owner: owner) {
                    return .fail(Self.rejectionCode(rejected), rejected)
                }
                pushUndo(L("meal")) { _, store in store.deleteMeal(mealID); return .succeed(["deleted": mealID.uuidString.lowercased()]) }
                return .succeed(["record": ["id": mealID.uuidString.lowercased(), "name": logged.name, "kcal": logged.kcal, "slot": slot.rawValue, "day": day.key],
                                 "undo": ["entity": "meal", "op": "delete", "id": mealID.uuidString.lowercased()]])
            } catch {
                let text = error.localizedDescription
                return .fail(text.contains("fasted") ? "FASTED_DAY" : "WRITE_FAILED", text)
            }
        case "update":
            guard let entry = mealEntry(id, store: store) else { return .fail("NOT_FOUND", L("That meal is not on this phone.")) }
            guard store.canEdit(entry) else { return .fail("EDIT_WINDOW_CLOSED", L("Meals older than seven days cannot be changed.")) }
            let before = entry
            let text = fields["name"] as? String ?? entry.text
            let kcal = (fields["kcal"] as? Double) ?? (fields["kcal"] as? Int).map(Double.init) ?? entry.kcal
            let protein = fields["protein_g"] as? Int ?? entry.protein
            let carb = fields["carb_g"] as? Int ?? entry.carb
            let fat = fields["fat_g"] as? Int ?? entry.fat
            let slot = (fields["slot"] as? String).flatMap(MealEntry.Slot.init(rawValue:)) ?? entry.slot
            let at = Self.clock(fields["at"], on: entry.day, fallback: entry.at)
            guard let owner = SupabaseClient.currentUserIdSnapshot() else { return .fail("SESSION_CHANGED") }
            let replacementID = UUID()
            let stamp = ISO8601DateFormatter(); stamp.formatOptions = [.withInternetDateTime]
            let replacementBody: [String: Any] = [
                "id": replacementID.uuidString.lowercased(), "user_day": entry.day.key, "slot": slot.rawValue, "name": text,
                "kcal": Int(kcal), "protein_g": protein, "carb_g": carb, "fat_g": fat,
                "logged_at": stamp.string(from: entry.day.pinningClock(at)), "confidence": "HIGH", "model_version": "voice-amendment-v1",
            ]
            do { try MealQueue.shared.enqueueAmend(mealID: entry.id, replacement: replacementBody, source: entry.source, revisions: entry.revisions + 1, ownerUserId: owner) }
            catch { return .fail("WRITE_FAILED", error.localizedDescription) }
            if let rejected = await settleMealOutbox(owner: owner) { return .fail(Self.rejectionCode(rejected), rejected) }
            let replacement = store.recentMeals.first(where: { $0.id == replacementID }) ?? store.meals.first(where: { $0.id == replacementID })
                ?? MealEntry(id: replacementID, day: entry.day, at: at, slot: slot, status: .confirmed, text: text, kcal: kcal, protein: protein, carb: carb, fat: fat, revisions: entry.revisions + 1, source: entry.source)
            pushUndo(L("meal change")) { _, store in
                store.amendMeal(replacementID, text: before.text, kcal: before.kcal, protein: before.protein, carb: before.carb, fat: before.fat, at: before.at, slot: before.slot)
                return .succeed(["restored": before.text])
            }
            return .succeed(["record": mealJSON(replacement), "undo": ["entity": "meal", "op": "update", "id": replacementID.uuidString.lowercased()]])
        case "delete":
            guard let id, let uuid = UUID(uuidString: id) else { return .fail("NOT_FOUND") }
            let entry = mealEntry(id, store: store)
            if let entry, !store.canEdit(entry) { return .fail("EDIT_WINDOW_CLOSED", L("Meals older than seven days cannot be changed.")) }
            guard let owner = SupabaseClient.currentUserIdSnapshot() else { return .fail("SESSION_CHANGED") }
            do { try MealQueue.shared.enqueueDelete(mealID: uuid, ownerUserId: owner) }
            catch { return .fail("WRITE_FAILED", error.localizedDescription) }
            if let rejected = await settleMealOutbox(owner: owner) { return .fail(Self.rejectionCode(rejected), rejected) }
            if let entry {
                pushUndo(L("meal delete")) { _, store in
                    let output: [String: Any] = ["name": entry.text, "kcal": Int(entry.kcal), "protein_g": entry.protein, "carb_g": entry.carb,
                                                 "fat_g": entry.fat, "confidence": "HIGH", "model_version": "voice-restore-v1"]
                    do {
                        let logged = try AIService.shared.logMealDraft(output, slot: entry.slot, day: entry.day, into: store)
                        return .succeed(["restored": logged.id.uuidString.lowercased()])
                    } catch { return .fail("WRITE_FAILED", error.localizedDescription) }
                }
            }
            return .succeed(["record": entry.map(mealJSON) ?? ["id": id], "deleted": true,
                             "undo": entry != nil ? ["entity": "meal", "op": "restore", "id": id] : [:]])
        case "restore":
            return await undo(store: store, permit: permit)
        default:
            return .fail("UNSUPPORTED")
        }
    }

    /// A queued meal change is only "done" once the server took it. Flush now and report the
    /// server's rejection, instead of answering ok for a row that will sit in the outbox.
    private func settleMealOutbox(owner: String) async -> String? {
        let queue = MealQueue.shared
        let before = Set(queue.rejected.map(\.id))
        await queue.flush()
        queue.refreshStatus(owner: owner)
        if let fresh = queue.rejected.first(where: { !before.contains($0.id) }) { return Self.rejectionCode(fresh.reason) + ": " + fresh.reason }
        if queue.pendingCount > 0, let error = queue.lastError, !error.isEmpty { return error }
        return nil
    }

    /// The server's word inside a rejection message, as a code the model can read.
    static func rejectionCode(_ reason: String) -> String {
        if reason.contains("FASTED") { return "FASTED_DAY" }
        if reason.contains("EDIT_WINDOW") { return "EDIT_WINDOW_CLOSED" }
        if reason.contains("NOT_FOUND") { return "NOT_FOUND" }
        if reason.contains("CONFLICT") { return "OPERATION_CONFLICT" }
        return "WRITE_FAILED"
    }

    private func markFasted(store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        // markTodayFasted refuses (as a bare CancellationError) while meal changes are still
        // queued; say which it was rather than "cancelled".
        if let owner = SupabaseClient.currentUserIdSnapshot() {
            await MealQueue.shared.flush()
            MealQueue.shared.refreshStatus(owner: owner)
            if MealQueue.shared.pendingCount > 0 {
                return .fail("PENDING_MEALS", L("Wait for pending meal changes to sync first, or remove them on the Fuel page."))
            }
        }
        do {
            try await permit.perform { try await store.markTodayFasted(day: store.today.day, confirmed: true) }
            return .succeed(["record": ["day": store.today.day.key, "fasted": true]])
        } catch {
            let code = Self.code(error)
            return .fail(code == "CANCELLED" ? "WRITE_FAILED" : code, code == "CANCELLED" ? L("The fasted mark was refused; check consent and that it is still today.") : Self.message(error))
        }
    }

    // MARK: weigh-in

    private func writeWeighIn(_ op: String, id: String?, fields: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        switch op {
        case "create":
            guard let kg = (fields["weight_kg"] as? Double) ?? (fields["weight_kg"] as? Int).map(Double.init), kg >= 20, kg <= 300 else {
                return .fail("BAD_ARGS", L("Weight must be between 20 and 300 kg."))
            }
            let day = Self.day(from: fields["day"], fallback: store.today.day)
            let at = Self.clock(fields["at"], on: day, fallback: day == store.today.day ? Date() : day.date.addingTimeInterval(12 * 3600))
            let w = WeighIn(id: UUID(), date: at, weightKg: kg, bodyFatPercent: nil, source: .measured, origin: .manual)
            store.addWeighIn(w)
            let wid = w.id
            pushUndo(L("weigh-in")) { permit, store in await self.deleteWeighIn(wid.uuidString.lowercased(), store: store, permit: permit) }
            return .succeed(["record": ["id": wid.uuidString.lowercased(), "kg": kg, "at": ISO8601DateFormatter().string(from: at)],
                             "undo": ["entity": "weigh_in", "op": "delete", "id": wid.uuidString.lowercased()]])
        case "delete":
            guard let id else { return .fail("NOT_FOUND") }
            let before = UUID(uuidString: id).flatMap { uuid in store.weighIns.first(where: { $0.id == uuid }) }
            let result = await deleteWeighIn(id, store: store, permit: permit)
            if result.ok, let before {
                pushUndo(L("weigh-in delete")) { _, store in
                    store.addWeighIn(WeighIn(id: UUID(), date: before.date, weightKg: before.weightKg, bodyFatPercent: before.bodyFatPercent, source: before.source, origin: before.origin))
                    return .succeed(["restored_kg": before.weightKg])
                }
            }
            return result
        default:
            return .fail("UNSUPPORTED")
        }
    }

    private func deleteWeighIn(_ id: String, store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return .fail("SESSION_CHANGED") }
        do {
            try await permit.perform {
                try await SupabaseClient.shared.deleteWhere("weigh_ins", column: "id", equals: id, expectedOwner: owner)
            }
        } catch { return .fail(Self.code(error) == "BAND_ERROR" ? "WRITE_FAILED" : Self.code(error), error.localizedDescription) }
        if let uuid = UUID(uuidString: id) { store.weighIns.removeAll { $0.id == uuid } }
        store.today.weightKg = store.weighIns.first?.weightKg
        return .succeed(["record": ["id": id], "deleted": true])
    }

    // MARK: sleep window

    /// #28 · the start and the end of one night, as the person wearing the band says they
    /// were. `correct_sleep_window` owns the rule about what a legal night is — the same
    /// entry the sleep page saves through — so this hands it two clock times and reports
    /// back whatever it says. The override is not an edit of the band's record: the window
    /// the band filed stays beside it, and `clear` gives it back.
    private func writeSleepNight(_ fields: [String: Any], store: DataStore,
                                 permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let dayKey = fields["day"] as? String else {
            return .fail("BAD_ARGS", L("Name the night by the day it was woken on."))
        }
        guard let owner = SupabaseClient.currentUserIdSnapshot() else { return .fail("SESSION_CHANGED") }
        let clearing = fields["clear"] as? Bool == true
        let start = fields["start"] as? String
        let end = fields["end"] as? String
        if !clearing && (start == nil || end == nil) {
            return .fail("BAD_ARGS", L("A corrected night needs a start and an end."))
        }
        do {
            let receipt = try await permit.perform { () async throws -> Any in
                if clearing {
                    return try await SupabaseClient.shared.rpc(
                        "clear_sleep_correction", args: ["p_user_day": dayKey], expectedOwner: owner)
                }
                return try await SupabaseClient.shared.rpc(
                    "correct_sleep_window",
                    args: ["p_user_day": dayKey, "p_start": start ?? "", "p_end": end ?? ""],
                    expectedOwner: owner)
            }
            await SleepCorrection.republish(day: dayKey, into: store)
            return .succeed(["record": (receipt as? [String: Any]) ?? ["user_day": dayKey]])
        } catch {
            let code = SleepCorrection.code(error)
            return .fail(code, SleepCorrection.message(code))
        }
    }

    // MARK: band

    private func bandReady() -> Result? {
        guard BoundBand.identifier != nil else { return .fail("BAND_DISCONNECTED", L("No band is paired.")) }
        guard Band.live.state == .connected else { return .fail("BAND_DISCONNECTED", L("The band is not connected.")) }
        return nil
    }

    private func findBand(stop: Bool, permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        if stop { await Band.live.stopFindHoop(); findOwner = nil; return .succeed(["vibrated": false]) }
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

    /// An alarm by id, or by the match the server could not resolve (no list rode with the turn).
    private static func pick(_ alarms: [BandAlarm], id: String?, match: [String: Any]) -> BandAlarm? {
        if let id, let n = Int(id), let hit = alarms.first(where: { $0.id == n }) { return hit }
        var hits = alarms
        if let time = match["time"] as? String, let (h, m) = parseTime(time) { hits = hits.filter { $0.hour == h && $0.minute == m } }
        if let label = match["label"] as? String, !label.isEmpty { hits = hits.filter { $0.text.localizedCaseInsensitiveContains(label) } }
        return (match["time"] != nil || match["label"] != nil) && hits.count == 1 ? hits[0] : nil
    }

    private static func alarmListLine(_ alarms: [BandAlarm]) -> String {
        alarms.isEmpty ? L("The band has no alarms.")
            : alarms.map { String(format: "%02d:%02d", $0.hour, $0.minute) + ($0.on ? "" : " (" + L("off") + ")") }.joined(separator: " · ")
    }

    /// Read the band's alarms once the band is there, so the first question after launch
    /// already has the list. Called after a successful foreground band sync.
    func primeAlarms() async {
        guard BoundBand.identifier != nil, Band.live.state == .connected else { return }
        if let list = try? await Band.live.readAlarms() { remember(list) }
    }

    private func writeAlarm(_ op: String, id: String?, match: [String: Any], fields: [String: Any], permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        do {
            switch op {
            case "create":
                guard let time = fields["time"] as? String, let (hour, minute) = Self.parseTime(time) else { return .fail("BAD_ARGS", L("Invalid time.")) }
                let days = (fields["days"] as? [Int]) ?? []
                let draft = BandAlarm(id: 0, hour: hour, minute: minute, on: fields["enabled"] as? Bool ?? true,
                                      repeatMask: Self.repeatMask(days: days), date: BandAlarm.onceDatePlaceholder,
                                      scene: BandAlarm.silentScene, text: String((fields["label"] as? String ?? "").prefix(20)))
                let result = try await permit.setAlarm(draft, read: { try await Band.live.readAlarms() },
                                                       write: { try await Band.live.writeAlarm($0) })
                remember(result.alarms)
                let newID = result.id
                pushUndo(L("alarm")) { permit, _ in
                    do {
                        let after = try await permit.deleteAlarm(newID, read: { try await Band.live.readAlarms() }, delete: { try await Band.live.deleteAlarm($0) })
                        self.remember(after); return .succeed(["alarms": after.map(Self.alarmJSON)])
                    } catch { return .fail(Self.code(error), error.localizedDescription) }
                }
                return .succeed(["record": result.alarms.first(where: { $0.id == newID }).map(Self.alarmJSON) ?? ["id": String(newID)],
                                 "alarms": result.alarms.map(Self.alarmJSON), "undo": ["entity": "alarm", "op": "delete", "id": String(newID)]])
            case "update":
                let alarms = try await permit.perform { try await Band.live.readAlarms() }
                remember(alarms)
                guard let current = Self.pick(alarms, id: id, match: match) else { return .fail("ALARM_NOT_FOUND", Self.alarmListLine(alarms)) }
                let alarmID = current.id
                var next = current
                if let on = fields["enabled"] as? Bool { next.on = on }
                if let time = fields["time"] as? String, let (h, m) = Self.parseTime(time) { next.hour = h; next.minute = m }
                if let days = fields["days"] as? [Int] { next.repeatMask = Self.repeatMask(days: days) }
                if let label = fields["label"] as? String { next.text = String(label.prefix(20)) }
                let after = try await permit.perform { try await Band.live.writeAlarm(BandAlarmMath.prepared(next)) }
                remember(after)
                pushUndo(L("alarm change")) { permit, _ in
                    do {
                        let back = try await permit.perform { try await Band.live.writeAlarm(BandAlarmMath.prepared(current)) }
                        self.remember(back); return .succeed(["alarms": back.map(Self.alarmJSON)])
                    } catch { return .fail(Self.code(error), error.localizedDescription) }
                }
                return .succeed(["record": after.first(where: { $0.id == alarmID }).map(Self.alarmJSON) ?? Self.alarmJSON(next),
                                 "alarms": after.map(Self.alarmJSON), "undo": ["entity": "alarm", "op": "update", "id": String(alarmID)]])
            case "delete":
                let listed = try await permit.perform { try await Band.live.readAlarms() }
                remember(listed)
                guard let target = Self.pick(listed, id: id, match: match) else { return .fail("ALARM_NOT_FOUND", Self.alarmListLine(listed)) }
                let alarmID = target.id
                let raw = String(alarmID)
                let before: BandAlarm? = target
                let after = try await permit.deleteAlarm(alarmID, read: { try await Band.live.readAlarms() },
                                                        delete: { try await Band.live.deleteAlarm($0) })
                remember(after)
                if let before {
                    pushUndo(L("alarm delete")) { permit, _ in
                        do {
                            let r = try await permit.setAlarm(before, read: { try await Band.live.readAlarms() }, write: { try await Band.live.writeAlarm($0) })
                            self.remember(r.alarms); return .succeed(["alarm_id": String(r.id)])
                        } catch { return .fail(Self.code(error), error.localizedDescription) }
                    }
                }
                return .succeed(["record": before.map(Self.alarmJSON) ?? ["id": raw], "deleted": true, "alarms": after.map(Self.alarmJSON)])
            default:
                return .fail("UNSUPPORTED")
            }
        } catch {
            return .fail(Self.code(error), error.localizedDescription)
        }
    }

    func remember(_ alarms: [BandAlarm]) {
        cachedAlarms = alarms
        alarmsReadAt = Date()
        alarmsOwner = (SupabaseClient.currentRequestSessionSnapshot(), BoundBand.identifier)
    }

    func remember(slots: [AutoMonitorSlot]) {
        cachedSlots = slots
        slotsOwner = BoundBand.identifier
    }

    func remember(read: AutoMonitoringRead) { remember(slots: Self.slots(from: read)) }

    /// The alarm list is read evidence for a turn, and a cold start has not read it. Read it
    /// once when the band is there so the next turn does not say "no alarms" for "not read".
    private var alarmsReadInFlight = false
    private func primeAlarmsIfNeeded() {
        guard alarmsReadAt == nil, !alarmsReadInFlight, BoundBand.identifier != nil, Band.live.state == .connected else { return }
        alarmsReadInFlight = true
        Task { @MainActor in
            defer { alarmsReadInFlight = false }
            if let list = try? await Band.live.readAlarms() { remember(list) }
        }
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

    private static func slotJSON(_ s: AutoMonitorSlot) -> [String: Any] {
        ["slot": s.kind.rawValue, "on": s.on, "interval_min": s.intervalMinutes,
         "interval_modifiable": s.intervalModifiable, "switch_modifiable": s.slotModifiable,
         // 0…180 whole minutes is 181 numbers; the model needs the range, not the list.
         "allowed_intervals": (!s.intervalModifiable ? [] : s.allowedIntervals.count <= 12 ? s.allowedIntervals.map { $0 as Any }
            : ["\(s.allowedIntervals.first ?? 0)–\(s.allowedIntervals.last ?? 0)" as Any]) as [Any],
         "window": s.supportsRange ? "\(s.startHour):00–\(s.endHour):00" : NSNull()]
    }

    private static func slots(from read: AutoMonitoringRead) -> [AutoMonitorSlot] {
        switch read {
        case .interval(let slots): return slots
        case .switches(let slots): return slots
        default: return []
        }
    }

    private func writeBandSetting(_ fields: [String: Any], permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        guard let raw = fields["slot"] as? String, let kind = AutoMonitorSlot.Kind(rawValue: raw) else { return .fail("BAD_ARGS") }
        do {
            let read = try await permit.perform { try await Band.live.readAutoMonitoring() }
            let slots = Self.slots(from: read)
            remember(slots: slots)
            guard let current = slots.first(where: { $0.kind == kind }) else { return .fail("UNSUPPORTED", L("This band does not report that slot.")) }
            var next = current
            if let on = fields["on"] as? Bool {
                guard current.slotModifiable else { return .fail("UNSUPPORTED", L("This firmware does not let the app switch that measurement; final, do not retry.")) }
                next.on = on
            }
            if let interval = fields["interval_min"] as? Int {
                guard current.intervalModifiable else { return .fail("UNSUPPORTED", L("This firmware owns the measurement interval; it cannot be changed from the app. Final, do not retry.")) }
                guard current.allowedIntervals.contains(interval) else {
                    let allowed = current.allowedIntervals
                    let line = allowed.count <= 12 ? allowed.map(String.init).joined(separator: ", ") : "\(allowed.first ?? 0)–\(allowed.last ?? 0)"
                    return .fail("BAD_ARGS", L("Allowed intervals: %@", line))
                }
                next.intervalMinutes = interval
                next.on = true
            }
            try await permit.perform { try await Band.live.writeAutoMonitoring(next) }
            if kind == .bloodGlucose { OpticalAutoSwitch.record(on: next.on) }
            let after = Self.slots(from: try await Band.live.readAutoMonitoring())
            remember(slots: after)
            pushUndo(L("band setting")) { permit, _ in
                do { try await permit.perform { try await Band.live.writeAutoMonitoring(current) }; return .succeed(Self.slotJSON(current)) }
                catch { return .fail(Self.code(error), error.localizedDescription) }
            }
            return .succeed(["record": (after.first(where: { $0.kind == kind }) ?? next).let(Self.slotJSON),
                             "undo": ["entity": "band_setting", "op": "update"]])
        } catch { return .fail(Self.code(error), error.localizedDescription) }
    }

    private func writeHeartRateAlarm(_ fields: [String: Any], permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        let on = fields["on"] as? Bool ?? hrAlarm?.on ?? true
        let low = fields["low"] as? Int ?? hrAlarm?.low ?? 40
        let high = fields["high"] as? Int ?? hrAlarm?.high ?? 160
        guard low < high, low >= 30, high <= 220 else { return .fail("BAD_ARGS", L("low must be below high, within 30–220.")) }
        do {
            let previous = hrAlarm
            let written = try await permit.perform { try await Band.live.writeSetting(.heartRateAlarm(on: on, low: low, high: high)) }
            guard case .heartRateAlarm(let wOn, let wLow, let wHigh) = written else { return .fail("BAND_ERROR") }
            hrAlarm = (wOn, wLow, wHigh)
            if let previous {
                pushUndo(L("heart-rate alarm")) { permit, _ in
                    do { _ = try await permit.perform { try await Band.live.writeSetting(.heartRateAlarm(on: previous.on, low: previous.low, high: previous.high)) }
                         self.hrAlarm = previous; return .succeed() }
                    catch { return .fail(Self.code(error), error.localizedDescription) }
                }
            }
            return .succeed(["record": ["on": wOn, "low": wLow, "high": wHigh]])
        } catch { return .fail(Self.code(error), error.localizedDescription) }
    }

    private func writeCadence(_ fields: [String: Any], permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let minutes = fields["minutes"] as? Int, SyncCadence.options.contains(minutes) else { return .fail("BAD_ARGS") }
        let before = SyncCadence.minutes
        SyncCadence.minutes = minutes
        Task { await Analytics.shared.track("SYNC_CADENCE_SET", ["MIN": minutes, "VIA": "voice"]) }
        pushUndo(L("sync cadence")) { _, _ in SyncCadence.minutes = before; return .succeed(["minutes": before]) }
        return .succeed(["record": ["minutes": minutes]])
    }

    // MARK: profile and preferences

    private func writeProfile(_ fields: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        let before = store.profile
        var profile = store.profile
        var edited: [String] = []
        if let name = fields["name"] as? String { profile.name = name; edited.append("display_name") }
        if let goal = (fields["goal"] as? String).flatMap(Goal.init(rawValue:)) {
            if profile.goal != goal { UserDefaults.standard.set(UserDay.containing(Date()).key, forKey: "nb.goal.changedDay") }
            profile.goal = goal; edited.append("goal")
        }
        if let units = fields["units"] as? String { profile.usesMetric = units != "imperial"; edited.append("units_metric") }
        if let h = (fields["height_cm"] as? Double) ?? (fields["height_cm"] as? Int).map(Double.init) { profile.heightCm = h; edited.append("height_cm") }
        if let birth = fields["birth_date"] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            guard let date = f.date(from: birth) else { return .fail("BAD_ARGS") }
            profile.birthdate = date; edited.append("birth_date")
        }
        if let sex = fields["sex"] as? String { profile.sexIsMale = sex == "male"; edited.append("sex") }
        var languageChanged: AppLocale?
        if let language = fields["language"] as? String {
            let next: AppLocale = language == "zh" ? .simplifiedChinese : .english
            if AppLanguage.shared.locale != next { languageChanged = AppLanguage.shared.locale; AppLanguage.shared.set(next) }
        }
        if !edited.isEmpty {
            store.profile = profile
            let saved = profile
            await Repository.shared.saveProfile(saved, editedFields: edited)
        } else if languageChanged == nil {
            return .fail("BAD_ARGS")
        }
        let previousLocale = languageChanged
        pushUndo(L("profile")) { _, store in
            if !edited.isEmpty { store.profile = before; await Repository.shared.saveProfile(before, editedFields: edited) }
            if let previousLocale { AppLanguage.shared.set(previousLocale) }
            return .succeed()
        }
        return .succeed(["record": ["name": profile.name, "goal": profile.goal.rawValue, "units": profile.usesMetric ? "metric" : "imperial",
                                    "height_cm": profile.heightCm, "language": AppLanguage.shared.locale.rawValue],
                         "changed": edited + (languageChanged != nil ? ["language"] : [])])
    }

    private func writeNotification(_ fields: [String: Any], permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let kind = fields["kind"] as? String, let on = fields["on"] as? Bool,
              ["morning", "training", "meals", "wrap", "energy", "band", "quiet"].contains(kind) else { return .fail("BAD_ARGS") }
        let key = "nb.notif.\(kind)"
        let before = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        UserDefaults.standard.set(on, forKey: key)
        NotificationReach.applyPrefs()
        pushUndo(L("notification")) { _, _ in UserDefaults.standard.set(before, forKey: key); NotificationReach.applyPrefs(); return .succeed() }
        return .succeed(["record": ["kind": kind, "on": on]])
    }

    private func writeHaptics(_ fields: [String: Any], permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let on = fields["on"] as? Bool else { return .fail("BAD_ARGS") }
        let before = HapticsSetting.shared.enabled
        HapticsSetting.shared.enabled = on
        pushUndo(L("phone haptics")) { _, _ in HapticsSetting.shared.enabled = before; return .succeed(["now": ["on": before], "what": "phone haptic feedback, not the band"]) }
        return .succeed(["record": ["on": on, "what": "phone haptic feedback, not the band"]])
    }

    private func dismissScreen(_ permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let handler = panelHandler else { return .fail("APP_BACKGROUND") }
        return handler.dismiss() ? .succeed(["cleared": true]) : .succeed(["cleared": false])
    }

    private func writeChatSession(_ op: String, id: String?, fields: [String: Any], permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        let chat = ChatStore.shared
        switch op {
        case "create":
            chat.startNewSession()
            return .succeed(["record": chat.sessions.first.map { ["id": $0.id, "title": $0.title] } ?? [:]])
        case "delete":
            if fields["all"] as? Bool == true { chat.clearAll(); return .succeed(["deleted": "all"]) }
            guard let id else { return .fail("NOT_FOUND") }
            return chat.deleteSession(id) ? .succeed(["deleted": id]) : .fail("NOT_FOUND", L("No saved chat has that id."))
        default:
            return .fail("UNSUPPORTED")
        }
    }

    // MARK: do

    private func runDo(_ args: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        let action = args["action"] as? String ?? ""
        switch action {
        case "device.find":    return await findBand(stop: args["stop"] as? Bool == true, permit: permit)
        case "device.sync":    return await syncBand(store: store, permit: permit)
        case "sport.start":    return await startSport(args, store: store, permit: permit)
        case "sport.stop":     return await stopSport(permit)
        case "measure.start":  return await startMeasure(args["kind"] as? String ?? "", store: store, permit: permit)
        case "plan.refresh":
            do { try permit.check() } catch { return .fail(Self.code(error)) }
            guard let handler = panelHandler else { return .fail("APP_BACKGROUND") }
            return handler.refreshPlan() ? .succeed(["started": true]) : .fail("CONSENT_REQUIRED")
        case "panel.confirm":
            do { try permit.check() } catch { return .fail(Self.code(error)) }
            guard let handler = panelHandler else { return .fail("APP_BACKGROUND") }
            let result = handler.confirmDraft()
            // Home queued the draft; the server has the last word (fasted day, consent…).
            if result.ok, let owner = SupabaseClient.currentUserIdSnapshot(), let rejected = await settleMealOutbox(owner: owner) {
                return .fail(Self.rejectionCode(rejected), rejected)
            }
            return result
        case "panel.dismiss":  return dismissScreen(permit)
        case "app.open":       return openPage(args, permit: permit)
        case "app.back":
            do { try permit.check() } catch { return .fail(Self.code(error)) }
            guard let router else { return .fail("APP_BACKGROUND") }
            if router.sheet != nil { router.sheet = nil } else { router.back() }
            return .succeed()
        case "app.home":
            do { try permit.check() } catch { return .fail(Self.code(error)) }
            guard let router else { return .fail("APP_BACKGROUND") }
            router.sheet = nil
            router.backToRoot()
            router.homePage = 0
            return .succeed()
        case "chat.new":
            do { try permit.check() } catch { return .fail(Self.code(error)) }
            ChatStore.shared.startNewSession()
            if let router { router.open(.chat(sessionID: ChatStore.shared.sessions.first?.id)) }
            return .succeed(["record": ChatStore.shared.sessions.first.map { ["id": $0.id] } ?? [:]])
        case "undo":           return await undo(store: store, permit: permit)
        default:               return .fail("UNKNOWN_TOOL")
        }
    }

    private func undo(store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard undoOwner == SupabaseClient.currentUserIdSnapshot(), let last = undoStack.popLast() else { return .fail("NOTHING_TO_UNDO") }
        let result = await last.perform(permit, store)
        // `now` is the state after the undo; `undone` names what was reversed.
        return result.ok ? .succeed((result.data ?? [:]).merging(["undone": last.label, "reverted": true]) { a, _ in a }) : result
    }

    // MARK: sport

    private static func sportMode(named raw: String?) -> SportModeOption {
        let name = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = SportModeCatalog.modes.first(where: { $0.name.lowercased() == name }) { return exact }
        if let partial = SportModeCatalog.modes.first(where: { !name.isEmpty && $0.name.lowercased().contains(name) }) { return partial }
        return SportModeCatalog.modes.first { $0.name == "Common" } ?? SportModeCatalog.modes[0]
    }

    private func startSport(_ args: [String: Any], store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        if let blocked = bandReady() { return blocked }
        let live = LiveSessionStore.shared
        guard live.session == nil else { return .fail("SESSION_ACTIVE") }
        let mode = Self.sportMode(named: args["mode"] as? String)
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

    // MARK: flows and pages

    private func startMeasure(_ kind: String, store: DataStore, permit: PhoneToolExecution.Execution) async -> Result {
        let measure: MeasureKind
        switch kind {
        case "balance_check":  measure = .ecg
        case "body_scan":      measure = .bodyComposition
        case "heart_rate":     measure = .heartRate
        // MeasureTakeover only measures these three; the other MeasureKinds fall into the
        // heart-rate path and would show a battery-check screen for a "blood oxygen" request.
        case "blood_oxygen", "temperature", "blood_pressure": return .fail("UNSUPPORTED", L("This band cannot measure that."))
        default: return .fail("BAD_ARGS")
        }
        if store.capabilities.knownUnsupported(measure) { return .fail("UNSUPPORTED", L("This band cannot measure that.")) }
        return await runFlow(.measure(measure), permit: permit)
    }

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

    /// docs/plans/2026-09-09-ai-tool-surface.md · the whole map: pages, sheets, windows, days.
    private func openPage(_ args: [String: Any], permit: PhoneToolExecution.Execution) -> Result {
        do { try permit.check() } catch { return .fail(Self.code(error)) }
        guard let router else { return .fail("APP_BACKGROUND") }
        var opened: [String: Any] = [:]
        let day = (args["day"] as? String).map { Self.day(from: $0, fallback: UserDay.containing(Date())) }
        if let page = args["page"] as? String {
            router.sheet = nil
            switch page {
            case "home":               router.backToRoot(); router.homePage = 0
            case "home.vitals":        router.backToRoot(); router.homePage = 1
            case "training":           router.open(.training)
            case "fuel":
                if let day, day != UserDay.containing(Date()) { router.open(.fuelDay(day)) } else { router.open(.fuel) }
            case "bodyBattery":        router.open(.bodyBattery)
            case "composition":        router.open(.composition(date: day?.date))
            case "profile":            router.open(.profile)
            case "measurements":       router.open(.measurements, from: .profile)
            case "device":             router.open(.device, from: .profile)
            case "device.battery":     router.open(.battery, from: .profile)
            case "device.autoMonitor": router.open(.deviceAutoMonitor, from: .profile)
            case "sportMode":          router.open(.sportMode)
            case "chat":               router.open(.chat(sessionID: args["session"] as? String))
            case "plan":               router.requestPlan()
            case "aiMemory":           router.open(.aiMemory, from: .profile)
            default:
                guard page.hasPrefix("vitals."), let metric = VitalsMetric(rawValue: String(page.dropFirst("vitals.".count))) else {
                    return .fail("UNKNOWN_PAGE", L("Unknown page."))
                }
                router.open(.vitals(metric))
            }
            opened["page"] = page
        }
        if let sheet = args["sheet"] as? String {
            let route: SheetRoute?
            switch sheet {
            case "weighIn": route = .weighIn
            case "profileEdit": route = .profileEdit
            case "goal": route = .goal
            case "units": route = .units
            case "language": route = .language
            case "notifications": route = .notifications
            case "appleHealth": route = .appleHealth
            case "bandAlarms": route = .bandAlarms
            case "findHoop": route = .findHoop
            case "bandAutoMonitor": route = .bandAutoMonitor
            case "syncCadence": route = .syncCadence
            case "export": route = .export
            case "about": route = .about
            case "privacy": route = .privacy
            case "plusMenu": route = .plusMenu
            case "deleteAccount": route = .deleteAccount
            case "signOut": route = .signOut
            case "unbind": route = .unbind
            case "disconnect": route = .disconnect
            case "firmware": route = .firmware
            default: route = nil
            }
            guard let route else { return .fail("UNKNOWN_PAGE", L("Unknown sheet.")) }
            // Device sheets live on the device page; profile sheets on profile. Land there first.
            switch route {
            case .bandAlarms, .findHoop, .bandAutoMonitor, .syncCadence, .unbind, .disconnect, .firmware:
                // The device page presents these itself; RootView's host has no view for them.
                if router.path.last != .device { router.open(.device, from: .profile) }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    router.deviceSheetRequest = route
                }
            case .profileEdit, .goal, .units, .language, .notifications, .appleHealth, .export, .about, .privacy, .deleteAccount, .signOut:
                if router.path.last != .profile { router.open(.profile) }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    router.sheet = route
                }
            default:
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    router.sheet = route
                }
            }
            opened["sheet"] = sheet
        }
        if let window = (args["window"] as? String).flatMap(RollingPills.init(rawValue:)) {
            router.windowRequest = window
            opened["window"] = window.rawValue
        }
        return .succeed(opened)
    }

    // MARK: helpers

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
}

private extension AutoMonitorSlot {
    func `let`<T>(_ f: (AutoMonitorSlot) -> T) -> T { f(self) }
}
