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
            } else {
                myHash = ""
            }
        }
    }

    let contactManager = ContactHashManager()
    let scanner = BLEScanner()
    let advertiser = BLEAdvertiser()

    private var staleTimer: Timer?

    init() {
        scanner.delegate = self
    }

    func startRadar() {
        guard !myHash.isEmpty else { return }

        advertiser.start(hash: myHash)
        scanner.start()
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
        staleTimer?.invalidate()
        staleTimer = nil
        status = .off
        nearbyContacts.removeAll()
    }

    var isRadarActive: Bool { status != .off }

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

    private func removeStaleContacts() {
        let cutoff = Date().addingTimeInterval(-MarcoConstants.staleTimeout)
        nearbyContacts.removeAll { $0.lastSeen < cutoff }
        if nearbyContacts.isEmpty && status == .found {
            status = .scanning
        }
    }
}

extension RadarViewModel: BLEScannerDelegate {
    nonisolated func scanner(_ scanner: BLEScanner, didDiscover hash: String, rssi: Int) {
        Task { @MainActor in
            processDiscovery(hash: hash, rssi: rssi)
        }
    }
}
