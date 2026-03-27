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
                meshManager?.updateMyHash(myHash)
            } else {
                myHash = ""
            }
        }
    }

    let contactManager = ContactHashManager()
    let scanner = BLEScanner()
    let advertiser = BLEAdvertiser()
    let landmarkTracker = LandmarkTracker()
    var meshManager: MeshManager?

    private var staleTimer: Timer?

    init() {
        scanner.delegate = self
    }

    func startRadar() {
        guard !myHash.isEmpty else { return }

        // Layer 2: Direct BLE
        advertiser.start(hash: myHash)
        scanner.start()

        // Layer 3: Mesh relay
        if meshManager == nil {
            meshManager = MeshManager(myHash: myHash, contactManager: contactManager)
            meshManager?.delegate = self
            meshManager?.setLandmarkProvider { [weak self] in
                self?.landmarkTracker.currentFingerprint() ?? []
            }
        }
        meshManager?.start()

        // Layer 4: Landmark tracking
        landmarkTracker.start()

        // Auto-search for all contact hashes via mesh
        searchContactsViaMesh()

        status = .scanning

        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeStaleContacts()
            }
        }
    }

    func stopRadar() {
        advertiser.stop()
        scanner.stop()
        meshManager?.stop()
        landmarkTracker.stop()
        staleTimer?.invalidate()
        staleTimer = nil
        status = .off
        nearbyContacts.removeAll()
    }

    var isRadarActive: Bool { status != .off }

    /// Search for up to 10 favorite/recent contacts via mesh
    private func searchContactsViaMesh() {
        guard let mesh = meshManager else { return }
        // Search for all contact hashes — in a real app you'd limit this
        // For demo, search for a few
        var count = 0
        for (hash, _) in contactManager.hashToContact {
            guard count < 10 else { break }
            mesh.searchForHash(hash)
            count += 1
        }
    }

    // MARK: - Discovery Processing

    private func processDiscovery(hash: String, rssi: Int) {
        guard hash != myHash else { return }

        let distance = DistanceEstimate.from(rssi: rssi)

        if let index = nearbyContacts.firstIndex(where: { $0.id == hash }) {
            nearbyContacts[index].rssi = rssi
            nearbyContacts[index].distance = distance
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
                distance: distance,
                firstSeen: Date(),
                lastSeen: Date(),
                rssiHistory: [rssi]
            )
            nearbyContacts.append(nearby)

            if contact != nil {
                status = .found
                print("[Radar] CONTACT FOUND: \(nearby.name) — \(distance.rawValue)")
            }
        }
    }

    private func processMeshFound(name: String, hash: String, hopCount: Int, rssiAtFind: Int, landmarks: [LandmarkSighting]?) {
        // Compute distance from landmarks if available
        var meshDistance: Double?
        if let theirLandmarks = landmarks {
            let myLandmarks = landmarkTracker.currentFingerprint()
            if let position = PositionEstimator.estimate(myFingerprint: myLandmarks, theirFingerprint: theirLandmarks) {
                meshDistance = position.estimatedDistance
                print("[Radar] Landmark position: \(position.estimatedDistance)m, confidence: \(position.confidence), shared: \(position.sharedLandmarkCount)")
            }
        }

        // Estimate distance from hop count if no landmark data
        let estimatedDistance = meshDistance ?? Double(hopCount) * 30.0

        let id = "mesh-\(hash)"
        if let index = nearbyContacts.firstIndex(where: { $0.id == id }) {
            nearbyContacts[index].lastSeen = Date()
        } else {
            let nearby = NearbyContact(
                id: id,
                name: name,
                phoneNumber: contactManager.lookup(hash)?.phoneNumber,
                rssi: rssiAtFind,
                distance: DistanceEstimate.from(rssi: rssiAtFind),
                firstSeen: Date(),
                lastSeen: Date(),
                rssiHistory: [rssiAtFind]
            )
            nearbyContacts.append(nearby)
            status = .found
            print("[Radar] MESH FOUND: \(name) — \(hopCount) hops, ~\(Int(estimatedDistance))m")
        }
    }

    private func removeStaleContacts() {
        let cutoff = Date().addingTimeInterval(-MarcoConstants.staleTimeout)
        nearbyContacts.removeAll { $0.lastSeen < cutoff }
        if nearbyContacts.isEmpty && status == .found {
            status = .scanning
        }
    }
}

// MARK: - BLEScannerDelegate

extension RadarViewModel: BLEScannerDelegate {
    nonisolated func scanner(_ scanner: BLEScanner, didDiscover hash: String, rssi: Int) {
        Task { @MainActor in
            processDiscovery(hash: hash, rssi: rssi)
        }
    }
}

// MARK: - MeshManagerDelegate

extension RadarViewModel: MeshManagerDelegate {
    nonisolated func meshManager(_ manager: MeshManager, didFindContact name: String, hash: String, hopCount: Int, rssiAtFind: Int, landmarks: [LandmarkSighting]?) {
        Task { @MainActor in
            processMeshFound(name: name, hash: hash, hopCount: hopCount, rssiAtFind: rssiAtFind, landmarks: landmarks)
        }
    }

    nonisolated func meshManager(_ manager: MeshManager, didRelaySearch hash: String, hops: Int) {
        // Stats tracking — could update UI
    }
}
