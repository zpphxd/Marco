import Foundation
import CoreBluetooth

protocol BLEScannerDelegate: AnyObject {
    func scanner(_ scanner: BLEScanner, didDiscover hash: String, rssi: Int)
}

class BLEScanner: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var totalDevicesSeen = 0

    weak var delegate: BLEScannerDelegate?

    private var centralManager: CBCentralManager?
    private var pendingStart = false
    private var seenPeripherals: Set<UUID> = []

    func start() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            pendingStart = true
        } else {
            beginScanning()
        }
    }

    func stop() {
        centralManager?.stopScan()
        isScanning = false
    }

    private func beginScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        // Scan for our custom service UUID
        cm.scanForPeripherals(
            withServices: [MarcoConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("[BLEScanner] Scanning...")
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        if central.state == .poweredOn && pendingStart {
            pendingStart = false
            beginScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue

        if !seenPeripherals.contains(peripheral.identifier) {
            seenPeripherals.insert(peripheral.identifier)
            totalDevicesSeen = seenPeripherals.count
        }

        // Match our custom Contact Radar beacon
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              localName.hasPrefix(MarcoConstants.hashPrefix)
        else { return }

        let hash = String(localName.dropFirst(MarcoConstants.hashPrefix.count))
        delegate?.scanner(self, didDiscover: hash, rssi: rssi)
    }
}
