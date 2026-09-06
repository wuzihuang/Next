import Foundation
import UIKit
import UserNotifications

/// Registers the APNs token and turns edges (ADR 0019) into requests.
/// The system dialog is still only reached through `NotificationPrimer`.
@MainActor
enum NotificationReach {
    static let deepLinkDidArrive = Notification.Name("NextBody.deepLink")
    static let disconnectAtKey = "nb.notif.disconnectAt"
    private static let tokenKey = "nb.notif.deviceToken"
    private static let dayKey = "nb.notif.day"
    private static let countKey = "nb.notif.dayCount"
    private static let deliveredKey = "nb.notif.delivered"
    private static let prevKcalKey = "nb.notif.prevKcal"
    private static let prevActiveKey = "nb.notif.prevActive"
    private static let prevReserveKey = "nb.notif.prevReserve"
    private static let highReserveKey = "nb.notif.highReserve"
    private static let wrapOpenedKey = "nb.notif.wrapOpened"
    static var currentPage: NotifyPage = .other

    struct Prefs {
        var morning: Bool
        var training: Bool
        var meals: Bool
        var wrap: Bool
        var energy: Bool
        var band: Bool
        var quiet: Bool

        static var current: Prefs {
            let d = UserDefaults.standard
            return Prefs(
                morning: d.object(forKey: "nb.notif.morning") as? Bool ?? true,
                training: d.object(forKey: "nb.notif.training") as? Bool ?? true,
                meals: d.object(forKey: "nb.notif.meals") as? Bool ?? true,
                wrap: d.object(forKey: "nb.notif.wrap") as? Bool ?? true,
                energy: d.object(forKey: "nb.notif.energy") as? Bool ?? true,
                band: d.object(forKey: "nb.notif.band") as? Bool ?? true,
                quiet: d.object(forKey: "nb.notif.quiet") as? Bool ?? true)
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    static func didGainAuthorization() async {
        await registerRemote()
        await Analytics.shared.track("NOTIF_AUTHORIZED", [:])
    }

    static func registerRemote() async {
        guard isAuthorized(await authorizationStatus()) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func rememberToken(_ data: Data) async {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        guard let uid = await SupabaseClient.shared.currentUserId else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        _ = try? await SupabaseClient.shared.upsert(
            "push_tokens",
            row: [
                "user_id": uid,
                "token": hex,
                "environment": environment,
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ],
            onConflict: "user_id,token",
            expectedOwner: uid)
        await Analytics.shared.track("NOTIF_TOKEN", ["ENV": environment])
    }

    private static var disconnectLivedThisProcess = false

    static func stampDisconnect(connected: Bool, at now: Date = Date(),
                                defaults: UserDefaults = .standard,
                                processLaunch: Bool = false) {
        if connected {
            defaults.removeObject(forKey: disconnectAtKey)
            disconnectLivedThisProcess = true
            return
        }
        if processLaunch, !disconnectLivedThisProcess {
            // Dead process: start the 4h clock now. Do not backfill the old stamp.
            defaults.set(now.timeIntervalSince1970, forKey: disconnectAtKey)
            disconnectLivedThisProcess = true
            return
        }
        if defaults.object(forKey: disconnectAtKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: disconnectAtKey)
        }
        disconnectLivedThisProcess = true
    }

    static func evaluate(store: DataStore, page: NotifyPage? = nil) {
        Task {
            let active = UIApplication.shared.applicationState == .active
            await refresh(today: store.today, history: store.history, store: store,
                          page: page ?? currentPage, appIsActive: active)
        }
    }

    /// Settings toggles cancel only. They must not backfill an edge that already exists.
    static func applyPrefs() {
        let prefs = Prefs.current
        var drop: [String] = []
        if !prefs.morning { drop.append(NotifyKind.morning.requestId) }
        if !prefs.training { drop.append(NotifyKind.training.requestId) }
        if !prefs.meals { drop.append(NotifyKind.meal.requestId) }
        if !prefs.wrap { drop.append(NotifyKind.daily.requestId) }
        if !prefs.energy { drop.append(NotifyKind.reserve.requestId) }
        if !prefs.band {
            drop.append(NotifyKind.bandBattery.requestId)
            drop.append(NotifyKind.bandAway.requestId)
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: drop)
        center.removeDeliveredNotifications(withIdentifiers: drop)
    }

    static func refresh(today: DailyMetrics, history: [DailyMetrics],
                        store: DataStore, page: NotifyPage, appIsActive: Bool) async {
        currentPage = page
        let status = await authorizationStatus()
        if isAuthorized(status) { await registerRemote() }

        let center = UNUserNotificationCenter.current()
        let prefs = Prefs.current
        guard isAuthorized(status) else {
            center.removePendingNotificationRequests(withIdentifiers: NotifyKind.allCases.map(\.requestId))
            return
        }

        let d = UserDefaults.standard
        rollDay(today.day.key, defaults: d)
        stampDisconnect(connected: store.band.connected, defaults: d, processLaunch: true)
        await harvestDelivered(defaults: d)

        // Lock-screen delivery is not on a page. Swallow only when the app is in front.
        let pageForMath: NotifyPage = appIsActive ? page : .other
        let snap = snapshot(today: today, history: history, store: store,
                            page: pageForMath, prefs: prefs, defaults: d)
        persistEdges(today: today, defaults: d)

        var keep = Set<String>()
        switch NotificationReachMath.decide(snap) {
        case .skip:
            break
        case .later(let kind, let when, let slot, let weekly):
            keep.insert(kind.requestId)
            await Analytics.shared.track("NOTIF_HOLD", ["KIND": kind.rawValue])
            await schedule(kind: kind, at: when, today: today, history: history,
                           mealSlot: slot, weekly: weekly)
        case .fire(let kind, let slot, let weekly):
            keep.insert(kind.requestId)
            await Analytics.shared.track("NOTIF_EDGE", ["KIND": kind.rawValue])
            await schedule(kind: kind, at: Date().addingTimeInterval(2), today: today,
                           history: history, mealSlot: slot, weekly: weekly)
        }

        if let awayAt = NotificationReachMath.awayFireAt(snap),
           !keep.contains(NotifyKind.bandAway.requestId),
           !keep.contains(NotifyKind.bandBattery.requestId),
           snap.deliveredCount < NotificationReachMath.budget {
            var when = awayAt
            if snap.quietEnabled, NotificationReachMath.isQuiet(when) {
                when = max(when, NotificationReachMath.quietEnd(after: max(when, snap.now)))
            }
            keep.insert(NotifyKind.bandAway.requestId)
            await schedule(kind: .bandAway, at: when, today: today, history: history,
                           mealSlot: nil, weekly: false)
        }

        let drop = NotifyKind.allCases.map(\.requestId).filter { !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: drop)
    }

    /// Compatibility for call sites that have not been given a store yet.
    static func refresh(today: DailyMetrics, history: [DailyMetrics], appIsActive: Bool) async {
        await refresh(today: today, history: history, store: DataStore.shared,
                      page: currentPage, appIsActive: appIsActive)
    }

    static func cancelMorning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotifyKind.morning.requestId])
        center.removeDeliveredNotifications(withIdentifiers: [NotifyKind.morning.requestId])
    }

    static func markPresented(_ notification: UNNotification) {
        guard let raw = notification.request.content.userInfo["kind"] as? String,
              let kind = NotifyKind(rawValue: raw) else { return }
        markDelivered(kind, defaults: .standard)
        Task { await Analytics.shared.track("NOTIF_DELIVERED", ["KIND": kind.rawValue]) }
    }

    static func handleResponse(_ response: UNNotificationResponse) {
        markPresented(response.notification)
        guard let raw = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: raw) else { return }
        NotificationCenter.default.post(name: deepLinkDidArrive, object: url)
    }

    static func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
        let raw = notification.request.content.userInfo["kind"] as? String
        let kind = raw.flatMap(NotifyKind.init(rawValue:))
        if let kind, NotificationReachMath.swallows(kind, page: currentPage) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
            markSeen(kind, defaults: .standard)
            return []
        }
        if kind != nil { markPresented(notification) }
        return [.banner, .sound, .list]
    }

    #if DEBUG
    static func debugFireNow() async {
        let content = UNMutableNotificationContent()
        content.title = L("LAST NIGHT")
        content.body = L("Last night is ready.")
        content.sound = .default
        content.userInfo = [
            "url": NotificationDeepLink.homePanel.url.absoluteString,
            "kind": NotifyKind.morning.rawValue,
        ]
        let req = UNNotificationRequest(
            identifier: NotifyKind.morning.requestId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        try? await UNUserNotificationCenter.current().add(req)
    }
    #endif

    private static func harvestDelivered(defaults: UserDefaults) async {
        let notes = await UNUserNotificationCenter.current().deliveredNotifications()
        for note in notes {
            guard let raw = note.request.content.userInfo["kind"] as? String,
                  let kind = NotifyKind(rawValue: raw) else { continue }
            markDelivered(kind, defaults: defaults)
        }
    }

    private static func snapshot(today: DailyMetrics, history: [DailyMetrics], store: DataStore,
                                 page: NotifyPage, prefs: Prefs, defaults: UserDefaults) -> NotifySnapshot {
        let now = MorningWidget.debugNow ?? Date()
        let m = history.first(where: { $0.day == today.day && !$0.reserveCurve.isEmpty }) ?? today
        let peak = m.bodyBatteryWakeAt ?? NotificationReachMath.wakePeak(
            dayStart: m.day.start,
            curve: m.reserveCurve.map { ($0.ts, $0.value) })
        let shown = defaults.string(forKey: MorningWidget.shownKey) == m.day.key
        let meals = (store.meals + store.recentMeals)
        let weekDays = UserDay.last(7, endingAt: today.day)
        let meals7 = meals.filter { weekDays.contains($0.day) && $0.status == .confirmed }.count
        let todayMeals = meals.filter { $0.day == today.day && $0.status == .confirmed }
        let slots = Set(todayMeals.map(\.slot))
        let prevKcal = defaults.object(forKey: prevKcalKey) as? Double
        let prevActive = defaults.object(forKey: prevActiveKey) as? Int
        let kcalRose = prevKcal.map { (today.eOutNow ?? 0) > $0 } ?? false
        let activeRose = prevActive.map { (today.activeMinutes ?? 0) > $0 } ?? false
        let prevReserve = defaults.object(forKey: prevReserveKey) as? Int
        let storedHigh = defaults.object(forKey: highReserveKey) as? Int
        let reserve = today.bodyBatteryForDisplay(at: now)
        let high = [storedHigh, reserve, today.bbWake].compactMap { $0 }.max()
        let disconnect: Date? = {
            guard defaults.object(forKey: disconnectAtKey) != nil else { return nil }
            return Date(timeIntervalSince1970: defaults.double(forKey: disconnectAtKey))
        }()
        let cal = Calendar.current
        let prevDay = today.day.adding(days: -1).start
        let weekRolled = cal.component(.weekOfYear, from: today.day.start)
            != cal.component(.weekOfYear, from: prevDay)
        let priorWeek = UserDay.last(7, endingAt: today.day.adding(days: -1))
        let validPrior = history.filter {
            priorWeek.contains($0.day) && ($0.bbWake != nil || $0.trainingLoad != nil)
        }.count
        let charge = store.band.displayedCharge
        let charging = charge == .charging || charge == .full
        return NotifySnapshot(
            now: now, quietEnabled: prefs.quiet,
            deliveredCount: defaults.integer(forKey: countKey),
            delivered: deliveredSet(defaults),
            page: page,
            morningOn: prefs.morning, trainingOn: prefs.training, mealsOn: prefs.meals,
            wrapOn: prefs.wrap, energyOn: prefs.energy, bandOn: prefs.band,
            wakePeak: peak, morningShown: shown,
            daySealed: today.day.end <= now,
            mealsInLast7Days: meals7,
            breakfastConfirmed: slots.contains(.breakfast),
            lunchConfirmed: slots.contains(.lunch),
            dinnerConfirmed: slots.contains(.dinner),
            moved: kcalRose || activeRose,
            trainingLoad: today.trainingLoad, targetLoad: today.targetLoad,
            reserveNow: reserve, prevReserve: prevReserve, bbWake: today.bbWake,
            dayHighReserve: high, liveSession: LiveSessionStore.shared.session != nil,
            reserveFresh: today.bodyBatteryFreshness(at: now) != .gone,
            hasNightCharge: m.reserveDrivers?.nightCharge != nil,
            hasConfirmedMeal: !todayMeals.isEmpty,
            weekRolled: weekRolled, priorWeekValidDays: validPrior,
            appOpenedAfterComplete: defaults.bool(forKey: wrapOpenedKey),
            bandBound: BoundBand.identifier != nil,
            bandConnected: store.band.connected,
            bandCharging: charging,
            bandPercent: store.band.lastBattery?.isPercent == true ? store.band.batteryPercent : nil,
            bandBars: store.band.lastBattery?.isPercent == false ? store.band.lastBattery?.level : nil,
            disconnectStarted: store.band.connected ? nil : disconnect)
    }

    private static func persistEdges(today: DailyMetrics, defaults: UserDefaults) {
        if let kcal = today.eOutNow { defaults.set(kcal, forKey: prevKcalKey) }
        if let active = today.activeMinutes { defaults.set(active, forKey: prevActiveKey) }
        if let r = today.bodyBattery {
            defaults.set(r, forKey: prevReserveKey)
            let high = max(defaults.object(forKey: highReserveKey) as? Int ?? r, r)
            defaults.set(high, forKey: highReserveKey)
        }
    }

    private static func rollDay(_ key: String, defaults: UserDefaults) {
        guard defaults.string(forKey: dayKey) != key else { return }
        defaults.set(key, forKey: dayKey)
        defaults.set(0, forKey: countKey)
        defaults.set("", forKey: deliveredKey)
        defaults.set(false, forKey: wrapOpenedKey)
        defaults.removeObject(forKey: prevKcalKey)
        defaults.removeObject(forKey: prevActiveKey)
        defaults.removeObject(forKey: prevReserveKey)
        defaults.removeObject(forKey: highReserveKey)
    }

    private static func deliveredSet(_ defaults: UserDefaults) -> Set<NotifyKind> {
        let raw = defaults.string(forKey: deliveredKey) ?? ""
        return Set(raw.split(separator: ",").compactMap { NotifyKind(rawValue: String($0)) })
    }

    private static func markDelivered(_ kind: NotifyKind, defaults: UserDefaults) {
        guard markSeen(kind, defaults: defaults) else { return }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    @discardableResult
    private static func markSeen(_ kind: NotifyKind, defaults: UserDefaults) -> Bool {
        var set = deliveredSet(defaults)
        guard set.insert(kind).inserted else { return false }
        defaults.set(set.map(\.rawValue).sorted().joined(separator: ","), forKey: deliveredKey)
        return true
    }

    private static func schedule(kind: NotifyKind, at fire: Date, today m: DailyMetrics,
                                 history: [DailyMetrics], mealSlot: String?, weekly: Bool) async {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = kind.requestId
        var link = kind.deepLink
        if kind == .meal { link = .fuel(slot: mealSlot) }
        content.userInfo = ["url": link.url.absoluteString, "kind": kind.rawValue]
        switch kind {
        case .morning:
            if let widget = MorningWidget.frame(today: m, history: history, now: fire, ignoreShown: true) {
                content.title = widget.title
                content.body = widget.sentence
            } else {
                content.title = L("LAST NIGHT")
                content.body = L("Last night is ready.")
            }
        case .meal:
            content.title = L(mealSlot?.uppercased() ?? "LUNCH")
            content.body = L("Have you eaten yet?")
        case .training:
            content.title = L("TRAINING")
            content.body = L("You are still under today's target.")
        case .daily:
            content.title = weekly ? L("THIS WEEK") : L("TODAY")
            content.body = wrapBody(today: m)
        case .reserve:
            content.title = L("BODY BATTERY")
            content.body = L("Reserve is low.")
        case .bandBattery:
            content.title = L("HOOP")
            content.body = L("Charge HOOP.")
        case .bandAway:
            content.title = L("HOOP")
            content.body = L("HOOP has been away for 4 hours.")
        }
        let soon = max(fire, Date().addingTimeInterval(2))
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: soon)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: kind.requestId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
        await Analytics.shared.track("NOTIF_SCHEDULED", [
            "KIND": kind.rawValue,
            "AT": ISO8601DateFormatter().string(from: soon),
        ])
    }

    private static func wrapBody(today m: DailyMetrics) -> String {
        var parts: [String] = []
        if let load = m.trainingLoad {
            parts.append(L("Load %@", String(format: "%g", load)))
        }
        if let inn = m.eIn {
            parts.append(L("%@ in", "\(Int(inn.rounded()))"))
        }
        if let bat = m.bodyBatteryForDisplay() {
            parts.append(L("reserve %@", "\(bat)"))
        }
        if parts.isEmpty { return L("The day is filling in.") }
        return parts.joined(separator: " · ") + "."
    }
}
