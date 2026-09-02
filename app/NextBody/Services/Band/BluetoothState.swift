import CoreBluetooth
import Foundation

/// 02 edge 2 · BLUETOOTH IS OFF is a state of the phone, not of the band, so it is read from
/// CoreBluetooth directly rather than inferred from a scan that finds nothing. One manager,
/// created the first time 02 needs it (which is where the system's Bluetooth prompt belongs).
@MainActor
final class BluetoothState: NSObject, ObservableObject {
    static let shared = BluetoothState()
    @Published private(set) var poweredOff = false
    private var central: CBCentralManager?

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
}

extension BluetoothState: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let off = central.state == .poweredOff
        Task { @MainActor in self.poweredOff = off }
    }
}
