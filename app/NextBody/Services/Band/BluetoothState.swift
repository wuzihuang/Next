import CoreBluetooth
import Foundation

/// 02 edge 2 · BLUETOOTH IS OFF is a state of the phone, not of the band, so it is read from
/// CoreBluetooth directly rather than inferred from a scan that finds nothing. One manager,
/// created the first time 02 needs it (which is where the system's Bluetooth prompt belongs).
@MainActor
final class BluetoothState: NSObject, ObservableObject {
    static let shared = BluetoothState()
    @Published private(set) var poweredOff = false
    /// iOS Bluetooth permission denied. A 15 s empty scan would otherwise look like
    /// NOTHING FOUND.
    @Published private(set) var permissionDenied = false
    private var central: CBCentralManager?

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// The manager's first callback is a run-loop later. Pairing reads this after that.
    func waitForState() async {
        start()
        for _ in 0..<20 {
            if let state = central?.state, state != .unknown, state != .resetting { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

extension BluetoothState: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let off = central.state == .poweredOff
        let denied = central.state == .unauthorized
        Task { @MainActor in
            self.poweredOff = off
            self.permissionDenied = denied
        }
    }
}
