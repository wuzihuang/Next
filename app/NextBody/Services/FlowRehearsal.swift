import Foundation

#if DEBUG
/// Rehearsal · walks sign-in → pairing → onboarding with every outcome faked as a success,
/// so the motion can be judged on a real phone without a server, a mailbox or a band.
/// Start it with the launch argument `-NB_REHEARSE YES` or the environment `NB_REHEARSE=1`.
/// Nothing is sent, saved or paired: no Supabase call, no BLE, no HealthKit, no consent row.
enum FlowRehearsal {
    static let on: Bool = {
        ProcessInfo.processInfo.environment["NB_REHEARSE"] == "1"
            || UserDefaults.standard.bool(forKey: "NB_REHEARSE")
    }()

    static let email = "rehearsal@nextbody.app"

    static let band = DiscoveredBand(id: "rehearsal-band", name: "NEXTBODY", rssi: -46, batteryPercent: 96)

    static let reading = BodyCompositionReading(
        bodyFatPercent: 18.4, fatMassKg: 11.6, leanMassKg: 51.4, muscleKg: 48.9, boneKg: 2.5,
        bodyWaterPercent: 57.2, proteinPercent: 18.1, subcutaneousFatPercent: 14.8,
        skeletalMusclePercent: 44.3, bmrKcal: 1420, bmi: 21.3, inputWeightKg: 63,
        muscleRatePercent: 77.6, waterKg: 36.0, proteinKg: 11.4)

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
