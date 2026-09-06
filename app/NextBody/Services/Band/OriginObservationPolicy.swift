import Foundation

/// Origin is a five-minute aggregate in the current band mapping. The SDK documents
/// interval values but does not promise whether its clock labels the start or end.
/// Treat it as a start, as the energy/load consumers do, and wait for the whole slot.
enum OriginObservationPolicy {
    static let slotDuration: TimeInterval = 5 * 60

    static func accepts(slot: Date, dayStart: Date, dayEnd: Date, readStartedAt: Date) -> Bool {
        slot >= dayStart && slot < dayEnd
            && slot.addingTimeInterval(slotDuration) <= min(dayEnd, readStartedAt)
    }
}
