import Foundation

/// Fixed workflow segments, not an estimate of remaining time. SDK dump completion is
/// only one segment; only the shared refresh's terminal success can publish 100%.
struct BandSyncProgress: Equatable, Sendable {
    enum Stage: String, Sendable {
        case searching, connecting, verifying, identity, battery, capabilities
        case reading, saving, updating, finishing, complete, stopped

        var buttonLabel: String {
            switch self {
            case .searching: "SEARCHING"
            case .connecting: "CONNECTING"
            case .verifying: "VERIFYING"
            case .identity, .battery, .capabilities, .reading: "READING"
            case .saving: "SAVING"
            case .updating: "UPDATING"
            case .finishing: "FINISHING"
            case .complete, .stopped: "SYNC"
            }
        }

        var label: String {
            switch self {
            case .searching: "SEARCHING FOR HOOP"
            case .connecting: "ESTABLISHING BLUETOOTH"
            case .verifying: "VERIFYING DEVICE"
            case .identity: "READING DEVICE INFO"
            case .battery: "READING BATTERY"
            case .capabilities: "PREPARING DEVICE DATA"
            case .reading: "READING THE BAND"
            case .saving: "SAVING READINGS"
            case .updating: "UPDATING RESULTS"
            case .finishing: "FINISHING SYNC"
            case .complete: "SYNC COMPLETE"
            case .stopped: "SYNC INCOMPLETE"
            }
        }
    }

    private(set) var stage: Stage = .searching
    private(set) var fraction: Double = 0
    private(set) var active = false
    private var filed = 0
    private var expected = 2

    mutating func begin() { self = .init(); active = true }
    mutating func show(_ next: Stage) {
        guard active, next != .complete, next != .stopped else { return }
        stage = next
        let floor: Double = switch next {
        case .searching: 0
        case .connecting: 0.03
        case .verifying: 0.08
        case .identity: 0.12
        case .battery: 0.16
        case .capabilities: 0.20
        case .reading: 0.25
        case .finishing: 0
        default: 0
        }
        fraction = max(fraction, floor)
    }
    mutating func read(_ value: Double) {
        guard active, value.isFinite else { return }
        fraction = max(fraction, 0.25 + 0.30 * min(1, max(0, value)))
    }
    mutating func expect(_ count: Int) { expected = max(1, max(filed, count)) }
    mutating func filedDay() {
        guard active else { return }
        filed += 1
        fraction = max(fraction, 0.55 + 0.35 * min(1, Double(filed) / Double(expected)))
    }
    mutating func updatingResults() {
        show(.updating)
        if active { fraction = max(fraction, 0.92) }
    }
    mutating func resultsLoaded() {
        if active { fraction = max(fraction, 0.96) }
    }
    mutating func finish(success: Bool) {
        guard active else { return }
        active = false
        stage = success ? .complete : .stopped
        if success { fraction = 1 }
    }
}
