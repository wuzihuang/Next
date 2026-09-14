import Foundation

/// Local lock for the idle plate. The picker stays in `IdlePlateLock`; this
/// only remembers yesterday's snapshot, the DEBUG visit cursor, and when
/// the bound band last dropped.
enum IdlePlateStore {
    private static let snapKey = "nb.idlePlate.snapshot"
    private static let downKey = "nb.idlePlate.disconnectStamp"
    private static let visitKey = "nb.idlePlate.visitPlate"

    static func load() -> IdlePlateLock.Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapKey) else { return nil }
        return try? JSONDecoder().decode(IdlePlateLock.Snapshot.self, from: data)
    }

    static func save(_ snap: IdlePlateLock.Snapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: snapKey)
    }

    static func loadVisitPlate() -> Int? {
        let plate = UserDefaults.standard.integer(forKey: visitKey)
        return plate > 0 ? plate : nil
    }

    static func saveVisitPlate(_ plate: Int) {
        UserDefaults.standard.set(plate, forKey: visitKey)
    }

    static func disconnectStamp() -> Date? {
        UserDefaults.standard.object(forKey: downKey) as? Date
    }

    /// First drop of this disconnect keeps the stamp so a four-hour away
    /// edge can fire. A reconnect clears it. A flap while already down
    /// does not restart the clock.
    static func noteConnection(_ connected: Bool) {
        if connected {
            UserDefaults.standard.removeObject(forKey: downKey)
        } else if UserDefaults.standard.object(forKey: downKey) == nil {
            UserDefaults.standard.set(Date(), forKey: downKey)
        }
    }
}
