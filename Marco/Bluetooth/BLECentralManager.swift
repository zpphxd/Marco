import Foundation
import CoreBluetooth

/// Delegate for Marco device discovery and data exchange
protocol MarcoPeerDelegate: AnyObject {
    func didDiscoverPeer(hash: String, rssi: Int, peripheral: CBPeripheral)
    func didReceiveLandmarks(_ landmarks: [LandmarkSighting], from hash: String)
    func didReceiveMeshMessage(_ data: Data, from peripheral: CBPeripheral)
    func didReceiveKeepalive(from peripheral: CBPeripheral)
    func didConnectPeer(_ peripheral: CBPeripheral)
    func didDisconnectPeer(_ peripheral: CBPeripheral)
}

/// Delegate for landmark tracking (non-Marco BLE devices)
protocol LandmarkScanDelegate: AnyObject {
    func didDiscoverLandmark(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int)
}

/// Single unified CBCentralManager that handles:
/// 1. Discovering Marco peers (by service UUID) → connects, reads GATT characteristics
/// 2. Discovering all BLE devices for landmark tracking
/// 3. Managing connections and keepalive cycles
/// 4. State Preservation and Restoration for background survival
@MainActor
class BLECentralManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var connectedPeerCount = 0

    weak var peerDelegate: MarcoPeerDelegate?
    weak var landmarkDelegate: LandmarkScanDelegate?

    private var centralManager: CBCentralManager?

    // Connected Marco peers: peripheral UUID → (peripheral, hash)
    private var connectedPeers: [UUID: (peripheral: CBPeripheral, hash: String?)] = [:]

    // Peers we're currently connecting to (prevent double-connect)
    private var connectingPeers: Set<UUID> = []

    // Keepalive timers: peripheral UUID → timer for writing to signal characteristic
    private var keepaliveTimers: [UUID: Timer] = [:]

    // Landmark read timers
    private var landmarkReadTimers: [UUID: Timer] = [:]

    // Track discovered signal characteristics per peripheral
    private var signalCharacteristics: [UUID: CBCharacteristic] = [:]
    private var meshCharacteristics: [UUID: CBCharacteristic] = [:]

    func start() {
        guard centralManager == nil else {
            beginScanning()
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: MarcoGATT.centralRestoreID]
        )
        print("[Central] Initialized with State Restoration ID: \(MarcoGATT.centralRestoreID)")
    }

    func stop() {
        centralManager?.stopScan()
        // Disconnect all peers
        for (_, info) in connectedPeers {
            centralManager?.cancelPeripheralConnection(info.peripheral)
        }
        connectedPeers.removeAll()
        connectingPeers.removeAll()
        keepaliveTimers.values.forEach { $0.invalidate() }
        keepaliveTimers.removeAll()
        landmarkReadTimers.values.forEach { $0.invalidate() }
        landmarkReadTimers.removeAll()
        signalCharacteristics.removeAll()
        meshCharacteristics.removeAll()
        isScanning = false
        connectedPeerCount = 0
        print("[Central] Stopped")
    }

    /// Send mesh data to a specific connected peer via GATT write
    func sendMeshMessage(_ data: Data, to peripheral: CBPeripheral) {
        guard let char = meshCharacteristics[peripheral.identifier] else {
            print("[Central] No mesh characteristic for \(peripheral.identifier.uuidString.prefix(8))")
            return
        }
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    /// Send mesh data to all connected peers except the source
    func broadcastMeshMessage(_ data: Data, excluding: CBPeripheral? = nil) {
        for (uuid, info) in connectedPeers {
            if info.peripheral.identifier == excluding?.identifier { continue }
            if let char = meshCharacteristics[uuid] {
                info.peripheral.writeValue(data, for: char, type: .withoutResponse)
            }
        }
    }

    var connectedPeripherals: [CBPeripheral] {
        connectedPeers.values.map(\.peripheral)
    }

    // MARK: - Scanning

    private func beginScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        // Scan for ALL devices — we dispatch to peer matching or landmark tracking
        cm.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("[Central] Scanning for all BLE devices...")
    }

    // MARK: - Connection Management

    private func connectToPeer(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        guard !connectingPeers.contains(uuid) && connectedPeers[uuid] == nil else { return }

        connectingPeers.insert(uuid)
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
        print("[Central] Connecting to Marco peer: \(uuid.uuidString.prefix(8))")
    }

    private func startKeepalive(for peripheral: CBPeripheral) {
        let uuid = peripheral.identifier

        // Write to signal characteristic every keepaliveDelay + 2s
        // (staggered from the peer's response delay)
        let interval = MarcoGATT.keepaliveDelay + 2.0
        keepaliveTimers[uuid]?.invalidate()
        keepaliveTimers[uuid] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.writeKeepalive(to: peripheral)
            }
        }

        // Also write immediately to start the cycle
        writeKeepalive(to: peripheral)

        print("[Central] Keepalive started for \(uuid.uuidString.prefix(8)) (interval: \(interval)s)")
    }

    private func writeKeepalive(to peripheral: CBPeripheral) {
        guard let char = signalCharacteristics[peripheral.identifier] else { return }
        // Herald pattern: write empty data with response to trigger keepalive
        peripheral.writeValue(Data(), for: char, type: .withResponse)
    }

    private func startLandmarkReading(for peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        landmarkReadTimers[uuid]?.invalidate()
        landmarkReadTimers[uuid] = Timer.scheduledTimer(withTimeInterval: MarcoGATT.landmarkReadInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.readLandmarks(from: peripheral)
            }
        }
    }

    private func readLandmarks(from peripheral: CBPeripheral) {
        // Find the landmark characteristic from discovered services
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == MarcoGATT.serviceUUID {
            for char in service.characteristics ?? [] where char.uuid == MarcoGATT.landmarkCharUUID {
                peripheral.readValue(for: char)
                return
            }
        }
    }

    private func cleanupPeer(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        connectedPeers.removeValue(forKey: uuid)
        connectingPeers.remove(uuid)
        keepaliveTimers[uuid]?.invalidate()
        keepaliveTimers.removeValue(forKey: uuid)
        landmarkReadTimers[uuid]?.invalidate()
        landmarkReadTimers.removeValue(forKey: uuid)
        signalCharacteristics.removeValue(forKey: uuid)
        meshCharacteristics.removeValue(forKey: uuid)
        connectedPeerCount = connectedPeers.count
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let states = ["unknown", "resetting", "unsupported", "unauthorized", "poweredOff", "poweredOn"]
        let name = central.state.rawValue < states.count ? states[central.state.rawValue] : "?"
        print("[Central] Bluetooth state: \(name)")

        Task { @MainActor in
            bluetoothState = central.state
            if central.state == .poweredOn {
                beginScanning()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        print("[Central] State restoration — resuming connections")

        // Restore connected peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            Task { @MainActor in
                for peripheral in peripherals {
                    peripheral.delegate = self
                    if peripheral.state == .connected {
                        connectedPeers[peripheral.identifier] = (peripheral, nil)
                        // Re-discover services to restore characteristic references
                        peripheral.discoverServices([MarcoGATT.serviceUUID])
                        print("[Central] Restored connected peer: \(peripheral.identifier.uuidString.prefix(8))")
                    }
                }
                connectedPeerCount = connectedPeers.count
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        guard rssi != 127 && rssi < 0 else { return }

        // Check if this is a Marco device (advertising our service UUID)
        let isMarcoDevice: Bool
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            isMarcoDevice = serviceUUIDs.contains(MarcoGATT.serviceUUID)
        } else {
            isMarcoDevice = false
        }

        Task { @MainActor in
            if isMarcoDevice {
                // Marco peer — connect to exchange data via GATT
                connectToPeer(peripheral)

                // If already connected and we know their hash, report RSSI update
                if let info = connectedPeers[peripheral.identifier], let hash = info.hash {
                    peerDelegate?.didDiscoverPeer(hash: hash, rssi: rssi, peripheral: peripheral)
                }
            } else {
                // Non-Marco device — landmark tracking
                landmarkDelegate?.didDiscoverLandmark(
                    peripheral: peripheral,
                    advertisementData: advertisementData,
                    rssi: rssi
                )
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[Central] Connected to \(peripheral.identifier.uuidString.prefix(8))")

        Task { @MainActor in
            connectingPeers.remove(peripheral.identifier)
            connectedPeers[peripheral.identifier] = (peripheral, nil)
            connectedPeerCount = connectedPeers.count

            // Discover Marco GATT service
            peripheral.discoverServices([MarcoGATT.serviceUUID])

            peerDelegate?.didConnectPeer(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[Central] Disconnected from \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "clean")")

        Task { @MainActor in
            cleanupPeer(peripheral)
            peerDelegate?.didDisconnectPeer(peripheral)

            // Auto-reconnect — iOS will keep trying indefinitely even in background
            central.connect(peripheral, options: nil)
            connectingPeers.insert(peripheral.identifier)
            print("[Central] Auto-reconnecting to \(peripheral.identifier.uuidString.prefix(8))")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[Central] Failed to connect: \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "unknown")")

        Task { @MainActor in
            connectingPeers.remove(peripheral.identifier)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            print("[Central] Service discovery failed: \(error?.localizedDescription ?? "no services")")
            return
        }

        for service in services where service.uuid == MarcoGATT.serviceUUID {
            // Discover all characteristics
            peripheral.discoverCharacteristics([
                MarcoGATT.hashCharUUID,
                MarcoGATT.landmarkCharUUID,
                MarcoGATT.signalCharUUID,
                MarcoGATT.meshCharUUID,
                MarcoGATT.uwbTokenCharUUID,
            ], for: service)
            print("[Central] Discovering characteristics for \(peripheral.identifier.uuidString.prefix(8))")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            print("[Central] Characteristic discovery failed: \(error?.localizedDescription ?? "none")")
            return
        }

        Task { @MainActor in
            for char in characteristics {
                switch char.uuid {
                case MarcoGATT.hashCharUUID:
                    // Read the peer's hash
                    peripheral.readValue(for: char)

                case MarcoGATT.signalCharUUID:
                    // Store reference and subscribe for keepalive notifications
                    signalCharacteristics[peripheral.identifier] = char
                    peripheral.setNotifyValue(true, for: char)
                    startKeepalive(for: peripheral)

                case MarcoGATT.meshCharUUID:
                    // Store reference and subscribe for mesh messages
                    meshCharacteristics[peripheral.identifier] = char
                    peripheral.setNotifyValue(true, for: char)

                case MarcoGATT.landmarkCharUUID:
                    // Read landmarks immediately, then periodically
                    peripheral.readValue(for: char)
                    startLandmarkReading(for: peripheral)

                case MarcoGATT.uwbTokenCharUUID:
                    // Read UWB token if available
                    peripheral.readValue(for: char)

                default:
                    break
                }
            }
            print("[Central] Characteristics discovered for \(peripheral.identifier.uuidString.prefix(8)): hash, signal, mesh, landmarks, uwb")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        Task { @MainActor in
            switch characteristic.uuid {
            case MarcoGATT.hashCharUUID:
                let hash = String(data: data, encoding: .utf8) ?? ""
                if !hash.isEmpty {
                    // Store hash for this peer
                    if var info = connectedPeers[peripheral.identifier] {
                        info.hash = hash
                        connectedPeers[peripheral.identifier] = info
                    }
                    print("[Central] GATT hash from \(peripheral.identifier.uuidString.prefix(8)): \(hash)")
                    // Read actual RSSI — didReadRSSI will report via peerDelegate
                    peripheral.readRSSI()
                }

            case MarcoGATT.landmarkCharUUID:
                if let landmarks = try? JSONDecoder().decode([LandmarkSighting].self, from: data) {
                    let hash = connectedPeers[peripheral.identifier]?.hash ?? "unknown"
                    print("[Central] GATT landmarks from \(peripheral.identifier.uuidString.prefix(8)): \(landmarks.count) sightings")
                    peerDelegate?.didReceiveLandmarks(landmarks, from: hash)
                }

            case MarcoGATT.signalCharUUID:
                // Keepalive notification received — write back immediately to sustain the cycle
                // This is reactive (not timer-based) so it works even when app was suspended
                print("[Central] Keepalive notification from \(peripheral.identifier.uuidString.prefix(8)) — writing back")
                writeKeepalive(to: peripheral)
                // Also read landmarks while we're awake
                readLandmarks(from: peripheral)
                peerDelegate?.didReceiveKeepalive(from: peripheral)

            case MarcoGATT.meshCharUUID:
                print("[Central] Mesh message from \(peripheral.identifier.uuidString.prefix(8)): \(data.count) bytes")
                peerDelegate?.didReceiveMeshMessage(data, from: peripheral)

            case MarcoGATT.uwbTokenCharUUID:
                print("[Central] UWB token from \(peripheral.identifier.uuidString.prefix(8)): \(data.count) bytes")
                // TODO: Phase 3 — pass to UWBManager

            default:
                break
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[Central] Notification state error for \(characteristic.uuid): \(error.localizedDescription)")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            if let hash = connectedPeers[peripheral.identifier]?.hash {
                peerDelegate?.didDiscoverPeer(hash: hash, rssi: RSSI.intValue, peripheral: peripheral)
            }
        }
    }
}
