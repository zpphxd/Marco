import Foundation
import CoreBluetooth

/// Publishes the Marco GATT service with characteristics for hash exchange,
/// landmark sharing, keepalive, and mesh relay.
///
/// Acts as the "server" side — other Marco devices connect and read/write
/// our characteristics to exchange data.
@MainActor
class BLEPeripheralManager: NSObject, ObservableObject {
    @Published var isAdvertising = false

    private var peripheralManager: CBPeripheralManager?
    private var service: CBMutableService?

    // Characteristic references for updating values
    private var hashCharacteristic: CBMutableCharacteristic?
    private var landmarkCharacteristic: CBMutableCharacteristic?
    private var signalCharacteristic: CBMutableCharacteristic?
    private var meshCharacteristic: CBMutableCharacteristic?
    private var uwbTokenCharacteristic: CBMutableCharacteristic?

    // Current data to serve
    private var myHash: Data = Data()
    private var landmarkData: Data = Data()
    private var uwbTokenData: Data?

    // Keepalive: track which centrals have written to signal, schedule notify back
    // Keyed by UUID (not CBCentral object) to survive state restoration
    private var pendingKeepalives: [UUID: (central: CBCentral, timer: Timer)] = [:]

    // Mesh: delegate for incoming mesh messages
    var onMeshMessageReceived: ((Data, CBCentral) -> Void)?
    var onSignalWriteReceived: ((CBCentral) -> Void)?

    func start() {
        guard peripheralManager == nil else { return }
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: MarcoGATT.peripheralRestoreID]
        )
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        pendingKeepalives.values.forEach { $0.timer.invalidate() }
        pendingKeepalives.removeAll()
        isAdvertising = false
        print("[Peripheral] Stopped")
    }

    // MARK: - Update Data

    func updateHash(_ hash: String) {
        myHash = Data(hash.utf8)
        hashCharacteristic?.value = myHash
        print("[Peripheral] Hash updated: \(hash)")
    }

    func updateLandmarks(_ sightings: [LandmarkSighting]) {
        // Serialize strongest landmarks first, fitting within GATT size limit
        // Each sighting is ~40 bytes JSON, so ~12 fit in 512 bytes
        let sorted = sightings.sorted { $0.rssi > $1.rssi }
        var toEncode = sorted
        while !toEncode.isEmpty {
            if let encoded = try? JSONEncoder().encode(toEncode),
               encoded.count <= MarcoGATT.maxCharacteristicSize {
                landmarkData = encoded
                landmarkCharacteristic?.value = landmarkData
                return
            }
            toEncode = Array(toEncode.dropLast()) // remove weakest signal
        }
        landmarkData = Data()
    }

    func updateUWBToken(_ tokenData: Data?) {
        uwbTokenData = tokenData
        uwbTokenCharacteristic?.value = tokenData
    }

    /// Send a mesh message to all subscribed centrals via notification
    func notifyMeshMessage(_ data: Data) {
        guard let char = meshCharacteristic, let pm = peripheralManager else { return }
        pm.updateValue(data, for: char, onSubscribedCentrals: nil)
    }

    // MARK: - Service Setup

    private func setupService() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }

        // Hash characteristic (Read)
        hashCharacteristic = CBMutableCharacteristic(
            type: MarcoGATT.hashCharUUID,
            properties: [.read],
            value: nil, // dynamic — return via delegate
            permissions: [.readable]
        )

        // Landmark characteristic (Read)
        landmarkCharacteristic = CBMutableCharacteristic(
            type: MarcoGATT.landmarkCharUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        // Signal/Keepalive characteristic (Write + Notify)
        // Herald pattern: .write (with response) ensures iOS processes the interaction
        signalCharacteristic = CBMutableCharacteristic(
            type: MarcoGATT.signalCharUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )

        // Mesh characteristic (Write Without Response + Notify)
        meshCharacteristic = CBMutableCharacteristic(
            type: MarcoGATT.meshCharUUID,
            properties: [.writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable]
        )

        // UWB Token characteristic (Read)
        uwbTokenCharacteristic = CBMutableCharacteristic(
            type: MarcoGATT.uwbTokenCharUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = CBMutableService(type: MarcoGATT.serviceUUID, primary: true)
        service.characteristics = [
            hashCharacteristic!,
            landmarkCharacteristic!,
            signalCharacteristic!,
            meshCharacteristic!,
            uwbTokenCharacteristic!,
        ]
        self.service = service

        pm.add(service)
        print("[Peripheral] GATT service added with 5 characteristics")
    }

    private func startAdvertising() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }

        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [MarcoGATT.serviceUUID],
            // No local name — iOS strips it in background anyway
            // The service UUID in overflow area is enough for discovery
        ])
        isAdvertising = true
        print("[Peripheral] Advertising Marco service UUID")
    }

    // MARK: - Keepalive

    private func scheduleKeepaliveResponse(for central: CBCentral) {
        let uuid = central.identifier
        pendingKeepalives[uuid]?.timer.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: MarcoGATT.keepaliveDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendKeepaliveNotification(to: central)
            }
        }
        pendingKeepalives[uuid] = (central: central, timer: timer)
    }

    private func sendKeepaliveNotification(to central: CBCentral) {
        guard let char = signalCharacteristic, let pm = peripheralManager else { return }

        let sent = pm.updateValue(Data(), for: char, onSubscribedCentrals: [central])

        if sent {
            print("[Peripheral] Keepalive notify → \(central.identifier.uuidString.prefix(8))")
        } else {
            print("[Peripheral] Keepalive notify queued (queue full)")
        }

        pendingKeepalives.removeValue(forKey: central.identifier)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let states = ["unknown", "resetting", "unsupported", "unauthorized", "poweredOff", "poweredOn"]
        let name = peripheral.state.rawValue < states.count ? states[peripheral.state.rawValue] : "?"
        print("[Peripheral] State: \(name)")

        if peripheral.state == .poweredOn {
            Task { @MainActor in
                setupService()
                startAdvertising()
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        print("[Peripheral] State restoration — resuming services")
        // iOS restored our services and advertising state
        // Re-setup any in-memory references
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            Task { @MainActor in
                for service in services {
                    for char in service.characteristics ?? [] {
                        if let mutable = char as? CBMutableCharacteristic {
                            switch mutable.uuid {
                            case MarcoGATT.hashCharUUID: hashCharacteristic = mutable
                            case MarcoGATT.landmarkCharUUID: landmarkCharacteristic = mutable
                            case MarcoGATT.signalCharUUID: signalCharacteristic = mutable
                            case MarcoGATT.meshCharUUID: meshCharacteristic = mutable
                            case MarcoGATT.uwbTokenCharUUID: uwbTokenCharacteristic = mutable
                            default: break
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("[Peripheral] Failed to add service: \(error.localizedDescription)")
        } else {
            print("[Peripheral] Service registered: \(service.uuid)")
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[Peripheral] Advertising failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read Requests

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        Task { @MainActor in
            let charUUID = request.characteristic.uuid
            var responseData: Data?

            switch charUUID {
            case MarcoGATT.hashCharUUID:
                responseData = myHash
                print("[Peripheral] Hash read by \(request.central.identifier.uuidString.prefix(8))")
            case MarcoGATT.landmarkCharUUID:
                responseData = landmarkData
                print("[Peripheral] Landmarks read by \(request.central.identifier.uuidString.prefix(8)): \(landmarkData.count) bytes")
            case MarcoGATT.uwbTokenCharUUID:
                responseData = uwbTokenData
                print("[Peripheral] UWB token read by \(request.central.identifier.uuidString.prefix(8))")
            default:
                peripheral.respond(to: request, withResult: .attributeNotFound)
                return
            }

            if let data = responseData {
                if request.offset > data.count {
                    peripheral.respond(to: request, withResult: .invalidOffset)
                    return
                }
                request.value = data.subdata(in: request.offset..<data.count)
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        }
    }

    // MARK: - Write Requests

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            Task { @MainActor in
                switch request.characteristic.uuid {
                case MarcoGATT.signalCharUUID:
                    // Keepalive write received — schedule notification response
                    print("[Peripheral] Keepalive write from \(request.central.identifier.uuidString.prefix(8))")
                    scheduleKeepaliveResponse(for: request.central)
                    onSignalWriteReceived?(request.central)

                case MarcoGATT.meshCharUUID:
                    // Mesh message received
                    if let data = request.value {
                        print("[Peripheral] Mesh message from \(request.central.identifier.uuidString.prefix(8)): \(data.count) bytes")
                        onMeshMessageReceived?(data, request.central)
                    }

                default:
                    break
                }
            }
        }
        // Respond to all write requests (required for .write type)
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
        }
    }

    // MARK: - Subscription

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("[Peripheral] \(central.identifier.uuidString.prefix(8)) subscribed to \(characteristic.uuid == MarcoGATT.signalCharUUID ? "signal" : characteristic.uuid == MarcoGATT.meshCharUUID ? "mesh" : "unknown")")
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            pendingKeepalives[central.identifier]?.timer.invalidate()
            pendingKeepalives.removeValue(forKey: central.identifier)
        }
        print("[Peripheral] \(central.identifier.uuidString.prefix(8)) unsubscribed")
    }
}
