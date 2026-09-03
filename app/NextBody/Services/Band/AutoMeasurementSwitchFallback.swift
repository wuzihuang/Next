import Foundation

/// How Veepoo encodes automatic-measurement on firmware that does **not** expose
/// `veepooSDKReadAutoMonitSwitchInfo` (`autoMonitSwitchType == 0`).
///
/// `VPPeripheralModel.deviceSwitchData` / `deviceSwitchTwoData` are 20-byte blobs.
/// Bytes 0..<2 are the header; from index 2 the vendor documents each flag as
/// 0 = absent, 1 = on, 2 = off. Blood oxygen is a pair of dedicated fields, not a
/// byte in those blobs.
enum AutoMeasurementSwitchFallback {
    enum Kind: String, Equatable, CaseIterable {
        case heartRate, bloodPressure, bloodGlucose, stress
        case bloodOxygen, temperature, hrv, bloodComponents
    }

    struct Reading: Equatable {
        var kind: Kind
        var on: Bool
    }

    /// Enough bytes to trust the local tables instead of probing over BLE.
    static func hasSwitchTables(switchData: [UInt8], switchTwoData: [UInt8]) -> Bool {
        switchData.count >= 13 || switchTwoData.count >= 12
    }

    static func readings(
        switchData: [UInt8],
        switchTwoData: [UInt8],
        oxygenSupported: Bool,
        oxygenOn: Bool
    ) -> [Reading] {
        var out: [Reading] = []
        if let on = flag(switchData, index: 4) { out.append(Reading(kind: .heartRate, on: on)) }
        if let on = flag(switchData, index: 5) { out.append(Reading(kind: .bloodPressure, on: on)) }
        if let on = flag(switchData, index: 12) { out.append(Reading(kind: .hrv, on: on)) }
        if oxygenSupported { out.append(Reading(kind: .bloodOxygen, on: oxygenOn)) }
        if let on = flag(switchTwoData, index: 4) { out.append(Reading(kind: .temperature, on: on)) }
        if let on = flag(switchTwoData, index: 7) { out.append(Reading(kind: .bloodGlucose, on: on)) }
        if let on = flag(switchTwoData, index: 9) { out.append(Reading(kind: .stress, on: on)) }
        if let on = flag(switchTwoData, index: 11) { out.append(Reading(kind: .bloodComponents, on: on)) }
        return out
    }

    /// 0 = this firmware has no such switch. 1 = on. 2 = off. Anything else is ignored.
    private static func flag(_ data: [UInt8], index: Int) -> Bool? {
        guard data.count > index else { return nil }
        switch data[index] {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }
}
