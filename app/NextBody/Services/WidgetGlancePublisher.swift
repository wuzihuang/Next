import Foundation

/// Writes the three home-strip numbers into the App Group the widgets read.
@MainActor
enum WidgetGlancePublisher {
    static func publish(from store: DataStore, numbersAt: Date? = nil, now: Date = Date()) {
        // `currentUserIdSnapshot` is empty until `restoreSession`. The Keychain
        // subject is already there on a returning launch — same gate HomeSnapshot uses.
        let signedIn = Band.allowsSeed
            || SupabaseClient.currentUserIdSnapshot() != nil
            || SessionKeychain.userId != nil
        var glance = WidgetFaceMath.Glance(
            numbersAt: numbersAt ?? now,
            battery: store.bodyBatteryNow,
            load: store.today.trainingLoad,
            eaten: store.today.eIn,
            target: store.today.targetIn,
            signedIn: signedIn,
            bandPercent: store.band.batteryPercent,
            bandCharge: store.band.displayedCharge.rawValue,
            heartRate: store.vitals.hr,
            stress: store.vitals.stress,
            sleepScore: store.sleepScores[store.today.day.key]?.score
                ?? store.today.sleepScore?.score,
            sleepMinutes: store.today.sleep?.totalMinutes,
            activeKcal: VitalsReadout.dayActiveKcal(store.today),
            steps: VitalsReadout.daySteps(store.today).map { Int($0.rounded()) },
            distanceM: VitalsReadout.dayMetres(store.today).map { Int($0.rounded()) },
            responsePoint: MealResponsePresentation.index(
                today: store.today,
                history: store.history,
                points: store.mealResponsePoints,
                zerosToday: store.mealResponseZerosToday).latestPoint,
            nightHrv: store.today.nightInputs?.hrv.map { Int($0.rounded()) },
            spo2: {
                guard let night = store.today.sleep else { return nil }
                let percents = night.spo2.filter { night.containsSleepTimestamp($0.ts) }.map(\.percent)
                return HealthSampleMapping.overnightOxygenSummary(percents)?.mean
            }())
        if numbersAt == nil,
           let previous = WidgetBridge.loadGlance(),
           previous.battery == glance.battery,
           previous.load == glance.load,
           previous.eaten == glance.eaten,
           previous.target == glance.target,
           previous.heartRate == glance.heartRate,
           previous.stress == glance.stress,
           previous.sleepScore == glance.sleepScore,
           previous.activeKcal == glance.activeKcal,
           previous.steps == glance.steps,
           previous.distanceM == glance.distanceM,
           previous.responsePoint == glance.responsePoint,
           previous.nightHrv == glance.nightHrv,
           previous.spo2 == glance.spo2 {
            glance.numbersAt = previous.numbersAt
        }
        WidgetBridge.save(glance)
    }

    static func clear() {
        WidgetBridge.clear()
    }
}
