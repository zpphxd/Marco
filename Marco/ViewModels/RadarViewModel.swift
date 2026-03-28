import Foundation
import Combine
import CoreBluetooth

@MainActor
class RadarViewModel: ObservableObject {
    @Published var status: RadarStatus = .off
    @Published var nearbyContacts: [NearbyContact] = []
    @Published var myHash: String = ""
    @Published var myPhoneNumber: String = "" {
        didSet {
            if !myPhoneNumber.isEmpty {
                myHash = CryptoUtils.hashPhoneNumber(myPhoneNumber)
                peripheralManager.updateHash(myHash)
                // Persist
                UserDefaults.standard.set(myPhoneNumber, forKey: "marco_phone_number")
            } else {
                myHash = ""
            }
        }
    }

    let contactManager = ContactHashManager()
    let centralManager = BLECentralManager()
    let peripheralManager = BLEPeripheralManager()
    let landmarkTracker = LandmarkTracker()
    let uwbManager = UWBManager()

    // Landmark fingerprints received from peers, keyed by hash
    private var receivedFingerprints: [String: [LandmarkSighting]] = [:]
    private var staleTimer: Timer?
    private var landmarkUpdateTimer: Timer?

    init() {
        centralManager.peerDelegate = self
        centralManager.landmarkDelegate = landmarkTracker

        // Wire mesh message handling
        peripheralManager.onMeshMessageReceived = { [weak self] data, central in
            Task { @MainActor [weak self] in
                self?.handleMeshMessage(data)
            }
        }

        // When someone reads our hash (they found us), connect back to them
        peripheralManager.onPeerConnected = { [weak self] central in
            Task { @MainActor [weak self] in
                print("[Radar] Peer \(central.identifier.uuidString.prefix(8)) read our hash — connecting back")
                self?.centralManager.connectBackToPeer(identifier: central.identifier)
            }
        }

        // Load persisted phone number
        if let saved = UserDefaults.standard.string(forKey: "marco_phone_number"), !saved.isEmpty {
            myPhoneNumber = saved
        }

        // Load contacts if already authorized
        contactManager.checkExistingAuthorization()
    }

    // MARK: - Lifecycle

    func startRadar() {
        guard !myHash.isEmpty else { return }

        peripheralManager.updateHash(myHash)
        peripheralManager.start()
        centralManager.start()
        landmarkTracker.start()

        // Publish UWB token if supported
        if uwbManager.isSupported, let tokenData = uwbManager.getTokenData() {
            peripheralManager.updateUWBToken(tokenData)
            print("[Radar] UWB supported — token published (\(tokenData.count) bytes)")
        }

        status = .scanning

        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeStaleContacts()
            }
        }

        // Update peripheral's landmark data periodically
        landmarkUpdateTimer = Timer.scheduledTimer(withTimeInterval: MarcoGATT.landmarkReadInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let fingerprint = self.landmarkTracker.currentFingerprint()
                self.peripheralManager.updateLandmarks(fingerprint)
            }
        }

        print("[Radar] Started — hash: \(myHash)")
    }

    func stopRadar() {
        peripheralManager.stop()
        centralManager.stop()
        landmarkTracker.stop()
        staleTimer?.invalidate()
        landmarkUpdateTimer?.invalidate()
        staleTimer = nil
        landmarkUpdateTimer = nil
        status = .off
        nearbyContacts.removeAll()
        receivedFingerprints.removeAll()
        print("[Radar] Stopped")
    }

    var isRadarActive: Bool { status != .off }

    // MARK: - Discovery Processing

    private var discoveryLogCounter = 0

    private func processDiscovery(hash: String, rssi: Int) {
        guard hash != myHash else { return }

        discoveryLogCounter += 1

        // Combined estimate using all available data
        let myLandmarks = landmarkTracker.currentFingerprint()
        let theirLandmarks = receivedFingerprints[hash] ?? []

        let position = PositionEstimator.combinedEstimate(
            myFingerprint: myLandmarks,
            theirFingerprint: theirLandmarks,
            directRSSI: rssi,
            uwbDistance: uwbManager.peerDistance,
            uwbDirection: uwbManager.peerDirection
        )

        if discoveryLogCounter % 10 == 0 {
            print("[Radar] Position: \(String(format: "%.1f", position.estimatedDistance))m method=\(position.method) confidence=\(String(format: "%.0f", position.confidence * 100))% shared=\(position.sharedLandmarkCount) uwb=\(position.uwbDistance.map { String(format: "%.2fm", $0) } ?? "none")")
        }

        let effectiveDistance: DistanceEstimate
        let ed = position.estimatedDistance
        switch ed {
        case ..<2: effectiveDistance = .veryClose
        case ..<5: effectiveDistance = .nearby
        case ..<15: effectiveDistance = .inRange
        default: effectiveDistance = .far
        }

        if let index = nearbyContacts.firstIndex(where: { $0.id == hash }) {
            nearbyContacts[index].rssi = rssi
            nearbyContacts[index].distance = effectiveDistance
            nearbyContacts[index].lastSeen = Date()
            nearbyContacts[index].rssiHistory.append(rssi)
            if nearbyContacts[index].rssiHistory.count > 20 {
                nearbyContacts[index].rssiHistory.removeFirst()
            }
        } else {
            let contact = contactManager.lookup(hash)
            let nearby = NearbyContact(
                id: hash,
                name: contact?.name ?? "Unknown Device",
                phoneNumber: contact?.phoneNumber,
                rssi: rssi,
                distance: effectiveDistance,
                firstSeen: Date(),
                lastSeen: Date(),
                rssiHistory: [rssi]
            )
            nearbyContacts.append(nearby)

            if contact != nil {
                status = .found
                print("[Radar] CONTACT FOUND: \(nearby.name) — \(effectiveDistance.rawValue)")
            }
        }

        if discoveryLogCounter % 10 == 0 {
            let isKnown = contactManager.lookup(hash) != nil
            print("[Radar] Signal: hash=\(hash.prefix(8)) RSSI=\(rssi) dist=\(effectiveDistance.rawValue) known=\(isKnown) contacts=\(nearbyContacts.count) landmarks=\(landmarkTracker.landmarkCount) peers=\(centralManager.connectedPeerCount)")
        }
    }

    // MARK: - Mesh

    private let dedup = DeduplicationCache()

    private func handleMeshMessage(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(MeshEnvelope.self, from: data) else { return }

        Task {
            switch envelope.type {
            case .search:
                if let search = envelope.unwrapSearch() {
                    await handleMeshSearch(search)
                }
            case .found:
                if let found = envelope.unwrapFound() {
                    handleMeshFound(found)
                }
            case .beacon:
                break // landmarks come via GATT characteristic read now
            }
        }
    }

    private func handleMeshSearch(_ search: MeshSearch) async {
        guard await dedup.shouldProcess(search.id) else { return }

        // Check if it's us they're looking for
        if search.queryHash == myHash {
            let found = MeshFound.create(search: search, rssi: 0, landmarks: landmarkTracker.currentFingerprint())
            if let data = MeshEnvelope.wrap(found) {
                centralManager.broadcastMeshMessage(data)
                print("[Mesh] I'm the target! Responding to search \(search.id.prefix(8))")
            }
            return
        }

        // Forward with decremented TTL
        guard search.ttl > 0 else { return }
        var forwarded = search
        forwarded.ttl -= 1
        forwarded.hopCount += 1
        if let data = MeshEnvelope.wrap(forwarded) {
            centralManager.broadcastMeshMessage(data)
            print("[Mesh] Relayed search for \(search.queryHash.prefix(8)) (TTL=\(forwarded.ttl))")
        }
    }

    private func handleMeshFound(_ found: MeshFound) {
        let contact = contactManager.lookup(found.queryHash)
        let name = contact?.name ?? "Unknown"
        print("[Mesh] FOUND: \(name) hash=\(found.queryHash.prefix(8)) hops=\(found.hopCount)")

        // Store their landmarks for position estimation
        if let landmarks = found.landmarks {
            receivedFingerprints[found.queryHash] = landmarks
        }

        let id = "mesh-\(found.queryHash)"
        if nearbyContacts.firstIndex(where: { $0.id == id }) == nil {
            let nearby = NearbyContact(
                id: id,
                name: name,
                phoneNumber: contact?.phoneNumber,
                rssi: -80,
                distance: .far,
                firstSeen: Date(),
                lastSeen: Date(),
                rssiHistory: [-80]
            )
            nearbyContacts.append(nearby)
            status = .found
        }
    }

    // MARK: - Stale Removal

    private func removeStaleContacts() {
        let cutoff = Date().addingTimeInterval(-MarcoConstants.staleTimeout)
        nearbyContacts.removeAll { $0.lastSeen < cutoff }
        if nearbyContacts.isEmpty && status == .found {
            status = .scanning
        }
    }
}

// MARK: - MarcoPeerDelegate

extension RadarViewModel: MarcoPeerDelegate {
    nonisolated func didDiscoverPeer(hash: String, rssi: Int, peripheral: CBPeripheral) {
        Task { @MainActor in
            processDiscovery(hash: hash, rssi: rssi)
        }
    }

    nonisolated func didReceiveLandmarks(_ landmarks: [LandmarkSighting], from hash: String) {
        Task { @MainActor in
            receivedFingerprints[hash] = landmarks
            print("[Radar] Stored \(landmarks.count) landmarks from \(hash.prefix(8))")
        }
    }

    nonisolated func didReceiveMeshMessage(_ data: Data, from peripheral: CBPeripheral) {
        Task { @MainActor in
            handleMeshMessage(data)
        }
    }

    nonisolated func didReceiveUWBToken(_ data: Data, from peripheral: CBPeripheral) {
        Task { @MainActor in
            if uwbManager.isSupported && !uwbManager.isRunning {
                uwbManager.startSession(withPeerTokenData: data)
                print("[Radar] Starting UWB session with peer \(peripheral.identifier.uuidString.prefix(8))")
            }
        }
    }

    nonisolated func didReceiveKeepalive(from peripheral: CBPeripheral) {
        // Connection is alive — nothing specific to do
    }

    nonisolated func didConnectPeer(_ peripheral: CBPeripheral) {
        print("[Radar] Peer connected: \(peripheral.identifier.uuidString.prefix(8))")
    }

    nonisolated func didDisconnectPeer(_ peripheral: CBPeripheral) {
        Task { @MainActor in
            uwbManager.stop() // Stop UWB when peer disconnects
        }
        print("[Radar] Peer disconnected: \(peripheral.identifier.uuidString.prefix(8))")
    }
}
