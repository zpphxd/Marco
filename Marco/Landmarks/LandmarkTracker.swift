import Foundation
import CoreBluetooth
import CryptoKit

// Known manufacturer IDs for logging
private let knownManufacturers: [UInt16: String] = [
    0x004C: "Apple", 0x0075: "Samsung", 0x0006: "Microsoft",
    0x00E0: "Google", 0x0059: "Nordic Semi", 0x0310: "Tile",
    0x01D1: "Xiaomi", 0x0157: "Huawei", 0x0087: "Garmin",
    0x012D: "Sony", 0x000F: "Broadcom", 0x0301: "Bose",
    0x05A7: "Sonos", 0x00DC: "Oral-B", 0x06D1: "LG",
    0x04A8: "Govee", 0x0A06: "Ecobee",
]

struct Landmark: Identifiable {
    let id: String
    var localName: String?
    var manufacturerID: UInt16?
    var rssiFilter: KalmanFilter
    var smoothedRSSI: Double
    var rssiSamples: [Double]
    var firstSeen: Date
    var lastSeen: Date
    var sampleCount: Int = 0

    var rssiVariance: Double {
        guard rssiSamples.count >= 3 else { return 999 }
        let mean = rssiSamples.reduce(0, +) / Double(rssiSamples.count)
        let variance = rssiSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rssiSamples.count)
        return sqrt(variance)
    }

    var isStable: Bool {
        let age = Date().timeIntervalSince(firstSeen)
        guard age > 15 else { return false }
        let stableVariance = rssiVariance < 5.0
        let likelyStaticMAC = manufacturerID != 0x004C
        let hasName = localName != nil && !(localName?.isEmpty ?? true)
        return stableVariance || (hasName && likelyStaticMAC && rssiVariance < 8.0)
    }

    var manufacturerName: String {
        guard let id = manufacturerID else { return "Unknown" }
        return knownManufacturers[id] ?? String(format: "0x%04X", id)
    }

    var stabilityReason: String {
        if rssiVariance < 5.0 { return "low-variance(\(String(format: "%.1f", rssiVariance)))" }
        let hasName = localName != nil && !(localName?.isEmpty ?? true)
        let notApple = manufacturerID != 0x004C
        if hasName && notApple && rssiVariance < 8.0 { return "named+static-mac" }
        if Date().timeIntervalSince(firstSeen) <= 15 { return "too-young" }
        return "unstable(var=\(String(format: "%.1f", rssiVariance)))"
    }
}

/// Tracks nearby BLE devices as positional landmarks.
/// Receives scan results from BLECentralManager via LandmarkScanDelegate.
/// No longer runs its own CBCentralManager — uses the unified one.
@MainActor
class LandmarkTracker: NSObject, ObservableObject {
    @Published var totalDevicesSeen = 0
    @Published var landmarkCount = 0

    private var landmarks: [String: Landmark] = [:]
    private var cleanupTimer: Timer?
    private var logCycle = 0
    private let maxSamples = 30

    var stableLandmarks: [Landmark] {
        landmarks.values.filter { $0.isStable }
    }

    func start() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanup()
            }
        }
        print("[Landmarks] Started (receiving scans from unified central)")
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        print("[Landmarks] Stopped")
    }

    func currentFingerprint() -> [LandmarkSighting] {
        let fp = stableLandmarks.map { landmark in
            LandmarkSighting(landmarkID: landmark.id, rssi: Int(landmark.smoothedRSSI))
        }
        if !fp.isEmpty && logCycle % 3 == 0 {
            print("[Landmarks] Fingerprint: \(fp.count) landmarks")
        }
        return fp
    }

    private func cleanup() {
        logCycle += 1
        let cutoff = Date().addingTimeInterval(-60)
        let before = landmarks.count
        landmarks = landmarks.filter { $0.value.lastSeen > cutoff }
        let removed = before - landmarks.count
        if removed > 0 {
            print("[Landmarks] Cleaned up \(removed) stale")
        }
        landmarkCount = stableLandmarks.count
        if logCycle % 3 == 0 {
            logReport()
        }
    }

    private func logReport() {
        let stable = stableLandmarks
        print("[Landmarks] === \(stable.count) stable / \(landmarks.count) total ===")
        for lm in stable.sorted(by: { $0.smoothedRSSI > $1.smoothedRSSI }).prefix(10) {
            let name = (lm.localName ?? "unnamed").prefix(20)
            let dist = PositionEstimator.rssiToDistance(lm.smoothedRSSI)
            print("[Landmarks]  ✓ \(name) | \(lm.manufacturerName) | RSSI=\(Int(lm.smoothedRSSI)) σ=\(String(format: "%.1f", lm.rssiVariance)) ~\(String(format: "%.1f", dist))m | \(lm.stabilityReason)")
        }
        if stable.count > 10 {
            print("[Landmarks]  ... +\(stable.count - 10) more")
        }
    }

    /// Generate a stable fingerprint ID for a device.
    /// NEVER uses peripheral.identifier (it's device-local, different on each phone).
    /// Uses only advertisement data that both phones would see identically.
    private func stableID(advertisementData: [String: Any]) -> String? {
        var components: [String] = []

        // Local name is the most stable identifier
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !name.isEmpty {
            components.append(name)
        }

        // Service UUIDs are stable across devices
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            components.append(services.map { $0.uuidString }.sorted().joined())
        }

        // Manufacturer company ID (first 2 bytes only — rest may rotate)
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2 {
            let companyID = String(format: "%02x%02x", mfg[0], mfg[1])
            components.append(companyID)
        }

        // Need at least 2 components for a cross-device stable ID
        guard components.count >= 2 else { return nil }

        let combined = components.joined(separator: "|")
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - LandmarkScanDelegate

extension LandmarkTracker: LandmarkScanDelegate {
    nonisolated func didDiscoverLandmark(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int) {
        // Skip Marco devices
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String, name.hasPrefix("MR-") {
            return
        }

        Task { @MainActor in
            // Generate cross-device stable ID — skip devices we can't identify reliably
            guard let id = stableID(advertisementData: advertisementData) else { return }

            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            var mfgID: UInt16?
            if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2 {
                mfgID = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)
            }

            if var landmark = landmarks[id] {
                let smoothed = landmark.rssiFilter.update(measurement: Double(rssi))
                landmark.smoothedRSSI = smoothed
                landmark.lastSeen = Date()
                landmark.sampleCount += 1
                landmark.rssiSamples.append(Double(rssi))
                if landmark.rssiSamples.count > maxSamples {
                    landmark.rssiSamples.removeFirst()
                }
                if name != nil { landmark.localName = name }
                landmarks[id] = landmark
            } else {
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
                    lastSeen: Date(),
                    sampleCount: 1
                )
                totalDevicesSeen += 1

                let mfgName = mfgID.flatMap { knownManufacturers[$0] } ?? "???"
                print("[Landmarks] NEW #\(totalDevicesSeen): \(name ?? "unnamed") | \(mfgName) | RSSI=\(rssi) | id=\(id.prefix(12))")
            }

            landmarkCount = stableLandmarks.count
        }
    }
}
