import Foundation
import CoreBluetooth

class BLEAdvertiser: NSObject, ObservableObject {
    @Published var isAdvertising = false

    private var peripheralManager: CBPeripheralManager?
    private var myHash: String = ""
    private var pendingStart = false

    func start(hash: String) {
        myHash = hash
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            pendingStart = true
        } else {
            beginAdvertising()
        }
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        print("[BLEAdvertiser] Stopped advertising")
    }

    private func beginAdvertising() {
        guard let pm = peripheralManager, pm.state == .poweredOn else {
            print("[BLEAdvertiser] Cannot advertise — Bluetooth not ready")
            return
        }

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [MarcoConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "\(MarcoConstants.hashPrefix)\(myHash)",
        ]

        pm.startAdvertising(advertisementData)
        isAdvertising = true
        print("[BLEAdvertiser] Advertising as \(MarcoConstants.hashPrefix)\(myHash)")
    }
}

extension BLEAdvertiser: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("[BLEAdvertiser] State: \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn && pendingStart {
            pendingStart = false
            beginAdvertising()
        }
    }
}
