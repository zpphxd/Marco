import Foundation
import CoreBluetooth
import CryptoKit

struct Landmark: Identifiable {
    let id: String
    var localName: String?
    var manufacturerID: UInt16?
    var rssiFilter: KalmanFilter
    var smoothedRSSI: Double
    var rssiSamples: [Double]
    var firstSeen: Date
    var lastSeen: Date

    var rssiVariance: Double {
        guard rssiSamples.count >= 3 else { return 999 }
        let mean = rssiSamples.reduce(0, +) / Double(rssiSamples.count)
        let variance = rssiSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rssiSamples.count)
        return sqrt(variance) // standard deviation
    }

    var isStable: Bool {
        let age = Date().timeIntervalSince(firstSeen)
        guard age > 15 else { return false } // need 15s of data

        // Low RSSI variance = stable position
        let stableVariance = rssiVariance < 5.0

        // Non-Apple devices more likely to have static MAC
        let likelyStaticMAC = manufacturerID != 0x004C

        // Has a name = likely infrastructure device
        let hasName = localName != nil && !(localName?.isEmpty ?? true)

        // Stable if low variance OR (has name + moderate variance)
        return stableVariance || (hasName && likelyStaticMAC && rssiVariance < 8.0)
    }
}

@MainActor
class LandmarkTracker: NSObject, ObservableObject {
    @Published var totalDevicesSeen = 0
    @Published var landmarkCount = 0

    private var landmarks: [String: Landmark] = [:]
    private var centralManager: CBCentralManager?
    private var cleanupTimer: Timer?
    private var isScanning = false

    // Max 30 seconds of RSSI samples per landmark
    private let maxSamples = 30

    var stableLandmarks: [Landmark] {
        landmarks.values.filter { $0.isStable }
    }

    func start() {
        guard !isScanning else { return }
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            beginScanning()
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanup()
            }
        }
    }

    func stop() {
        centralManager?.stopScan()
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        isScanning = false
    }

    func currentFingerprint() -> [LandmarkSighting] {
        stableLandmarks.map { landmark in
            LandmarkSighting(landmarkID: landmark.id, rssi: Int(landmark.smoothedRSSI))
        }
    }

    private func beginScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else { return }

        // Scan for ALL devices to find landmarks
        cm.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    private func cleanup() {
        let cutoff = Date().addingTimeInterval(-60)
        let before = landmarks.count
        landmarks = landmarks.filter { $0.value.lastSeen > cutoff }
        let removed = before - landmarks.count
        if removed > 0 {
            print("[Landmarks] Cleaned up \(removed) stale landmarks")
        }
        landmarkCount = stableLandmarks.count
        logLandmarkSummary()
    }

    private func logLandmarkSummary() {
        let stable = stableLandmarks
        guard !stable.isEmpty else { return }
        print("[Landmarks] === \(stable.count) stable / \(landmarks.count) total ===")
        for lm in stable.sorted(by: { $0.smoothedRSSI > $1.smoothedRSSI }) {
            let name = lm.localName ?? "unnamed"
            let mfg = lm.manufacturerID.map { String(format: "0x%04X", $0) } ?? "???"
            let age = Int(Date().timeIntervalSince(lm.firstSeen))
            print("[Landmarks]  \(name) | mfg=\(mfg) | RSSI=\(Int(lm.smoothedRSSI)) | var=\(String(format: "%.1f", lm.rssiVariance)) | \(age)s | id=\(lm.id.prefix(12))")
        }
    }

    /// Generate a stable fingerprint ID for a device
    private func stableID(peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        // Try manufacturer data + service UUIDs + name for a stable fingerprint
        var components: [String] = []

        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            // Use first 4 bytes of manufacturer data (company ID + type)
            let prefix = mfg.prefix(4)
            components.append(prefix.map { String(format: "%02x", $0) }.joined())
        }

        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            components.append(services.map { $0.uuidString }.sorted().joined())
        }

        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !name.isEmpty {
            components.append(name)
        }

        if let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            components.append("tx\(txPower)")
        }

        // If we have enough data for a stable fingerprint, hash it
        if components.count >= 2 {
            let combined = components.joined(separator: "|")
            let digest = SHA256.hash(data: Data(combined.utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }

        // Fall back to peripheral UUID (works for non-rotating devices)
        return peripheral.identifier.uuidString
    }
}

// MARK: - CBCentralManagerDelegate

extension LandmarkTracker: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            Task { @MainActor in
                beginScanning()
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
        guard rssi != 127 && rssi < 0 else { return } // invalid readings

        Task { @MainActor in
            let id = stableID(peripheral: peripheral, advertisementData: advertisementData)
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String

            var mfgID: UInt16?
            if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2 {
                mfgID = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)
            }

            if var landmark = landmarks[id] {
                // Update existing
                let smoothed = landmark.rssiFilter.update(measurement: Double(rssi))
                landmark.smoothedRSSI = smoothed
                landmark.lastSeen = Date()
                landmark.rssiSamples.append(Double(rssi))
                if landmark.rssiSamples.count > maxSamples {
                    landmark.rssiSamples.removeFirst()
                }
                if name != nil { landmark.localName = name }
                landmarks[id] = landmark
            } else {
                // New device
                var filter = KalmanFilter()
                let smoothed = filter.update(measurement: Double(rssi))
                landmarks[id] = Landmark(
                    id: id,
                    localName: name,
                    manufacturerID: mfgID,
                    rssiFilter: filter,
                    smoothedRSSI: smoothed,
                    rssiSamples: [Double(rssi)],
                    firstSeen: Date(),
                    lastSeen: Date()
                )
                totalDevicesSeen += 1
            }

            landmarkCount = stableLandmarks.count
        }
    }
}
