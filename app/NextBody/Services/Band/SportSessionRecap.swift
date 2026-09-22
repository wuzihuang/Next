import Foundation
#if canImport(NextBodyLocalData)
import NextBodyLocalData
#endif

/// A completed session's observations. Calculated training load is always read from
/// the current server settlement; this document never becomes a second load ledger.
struct SportSessionRecap: Equatable, Codable, Identifiable, Sendable {
    var title: String
    var startedAt: Date
    var endedAt: Date
    var seconds: Int
    var avgHR: Int?
    var peakHR: Int?
    var kcal: Double
    var caloriesEstimated: Bool
    var curve: [Double]
    var zoneMinutes: [Double]
    var aerobicMinutes: Int
    var anaerobicMinutes: Int
    var conclusion: String
    var sessionID: UUID?
    var ownerUserID: String?
    var loadBefore: Double?
    var loadAfter: Double?
    var curvePoints: [SportRecapMath.Beat]? = nil
    var observedSeconds: Double? = nil
    var hasCalories: Bool? = nil
    var restHR: Int? = nil
    var maxHR: Int? = nil

    var id: String { sessionID?.uuidString ?? String(startedAt.timeIntervalSince1970) }
    var hasZones: Bool { (observedSeconds ?? (avgHR == nil ? 0 : 1)) > 0 }
    var hasEnergy: Bool { hasCalories ?? (kcal > 0) }
    var isValid: Bool {
        startedAt.timeIntervalSince1970.isFinite && endedAt.timeIntervalSince1970.isFinite
            && endedAt >= startedAt && endedAt.timeIntervalSince(startedAt) <= 86_400
            && (0...86_400).contains(seconds) && kcal.isFinite && (0...100_000).contains(kcal)
            && zoneMinutes.count == 5 && zoneMinutes.allSatisfy { $0.isFinite && (0...1440).contains($0) }
            && (curvePoints?.allSatisfy { (1...250).contains($0.bpm)
                && $0.at.timeIntervalSince1970.isFinite } ?? true)
    }
}

/// Account-scoped cache and durable outbox share a transaction. A crash between
/// upload and acknowledgement repeats the same immutable session ID and payload.
struct SportRecapArchive {
    static let kind = "sport-recap"
    static let key = "sport-recaps"
    let local: LocalDataStore

    func read(owner: String) throws -> [SportSessionRecap] {
        guard let data = try local.readDocument(account: owner, key: Self.key) else { return [] }
        return try JSONDecoder().decode([SportSessionRecap].self, from: data)
            .filter { $0.ownerUserID == owner && $0.isValid }
    }

    func stage(_ recap: SportSessionRecap, owner: String) throws {
        guard recap.ownerUserID == owner, recap.isValid, let id = recap.sessionID else {
            throw LocalDataStore.Failure.invalidOwner
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let merged = try merge([recap], owner: owner)
        try local.enqueue(operation: LocalOperation(id: "sport-recap:\(id.uuidString.lowercased())",
            account: owner, kind: Self.kind, payload: try encoder.encode(recap)),
            documentKey: Self.key, document: try encoder.encode(merged))
    }

    /// One unsupported or damaged in-memory record cannot block already valid work.
    /// Failed records stay with the caller so retry never silently discards observations.
    func stagePending(_ recaps: [SportSessionRecap], owner: String) -> [SportSessionRecap] {
        recaps.filter { recap in
            do { try stage(recap, owner: owner); return false }
            catch { return true }
        }
    }

    func cache(_ recaps: [SportSessionRecap], owner: String) throws {
        try local.writeDocument(account: owner, key: Self.key,
            data: JSONEncoder().encode(merge(recaps, owner: owner)))
    }

    private func merge(_ recaps: [SportSessionRecap], owner: String) throws -> [SportSessionRecap] {
        var rows = Dictionary(try read(owner: owner).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for recap in recaps where recap.ownerUserID == owner { rows[recap.id] = recap }
        return rows.values.sorted { $0.startedAt > $1.startedAt }
    }
}
