import Foundation
import HealthKit

/// F5 · Apple Health, read only. Sex, date of birth, height and weight — the four numbers
/// every calorie and body-composition figure is built from — and nothing else.
///
/// ⚠️ Read permission cannot be probed: after the sheet, HealthKit reports "not determined"
/// for a refused read exactly as it does for a granted one with no data behind it. So this
/// service never claims to know the answer; an empty read is "nothing came back". The
/// consent screen promises never to write, and `toShare` is empty to keep that promise.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    struct Baseline {
        var sexIsMale: Bool?
        var born: DateComponents?
        var heightCm: Double?
        var weightKg: Double?
        var weightAt: Date?
        var isEmpty: Bool { sexIsMale == nil && born == nil && heightCm == nil && weightKg == nil }
    }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        if let t = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { s.insert(t) }
        if let t = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .height) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) { s.insert(t) }
        return s
    }

    /// Shows the system sheet the first time; a no-op after. Returns false only when Health
    /// is not on this device at all.
    @discardableResult
    func requestRead() async -> Bool {
        guard available else { return false }
        do { try await store.requestAuthorization(toShare: [], read: readTypes) } catch { return false }
        UserDefaults.standard.set(true, forKey: "nb.health.asked")
        return true
    }

    /// True once the sheet has been shown — the only thing about the permission we can know.
    var asked: Bool { UserDefaults.standard.bool(forKey: "nb.health.asked") }

    func readBaseline() async -> Baseline {
        var b = Baseline()
        guard available else { return b }
        if let sex = try? store.biologicalSex().biologicalSex, sex != .notSet {
            b.sexIsMale = sex == .male
        }
        if let dob = try? store.dateOfBirthComponents(), dob.year != nil {
            b.born = DateComponents(year: dob.year, month: dob.month, day: dob.day)
        }
        if let h = await latest(.height) {
            b.heightCm = h.quantity.doubleValue(for: .meterUnit(with: .centi))
        }
        if let w = await latest(.bodyMass) {
            b.weightKg = w.quantity.doubleValue(for: .gramUnit(with: .kilo))
            b.weightAt = w.endDate
        }
        return b
    }

    func latestWeight() async -> (kg: Double, at: Date)? {
        guard available, let w = await latest(.bodyMass) else { return nil }
        return (w.quantity.doubleValue(for: .gramUnit(with: .kilo)), w.endDate)
    }

    private func latest(_ id: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(q)
        }
    }
}
