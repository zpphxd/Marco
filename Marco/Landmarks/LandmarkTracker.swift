import Foundation
import CoreBluetooth
import CryptoKit

// Known manufacturer IDs for logging
private let knownManufacturers: [UInt16: String] = [
    0x004C: "Apple",
    0x0075: "Samsung",
    0x0006: "Microsoft",
    0x00E0: "Google",
    0x0059: "Nordic Semi",
    0x0310: "Tile",
    0x01D1: "Xiaomi",
    0x0157: "Huawei",
    0x0087: "Garmin",
    0x012D: "Sony",
    0x000F: "Broadcom",
    0x0301: "Bose",
    0x05A7: "Sonos",
    0x00DC: "Oral-B",
    0x06D1: "LG",
    0x04A8: "Govee",
    0x0A06: "Ecobee",
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

@MainActor
class LandmarkTracker: NSObject, ObservableObject {
    @Published var totalDevicesSeen = 0
    @Published var landmarkCount = 0

    private var landmarks: [String: Landmark] = [:]
    private var centralManager: CBCentralManager?
    private var cleanupTimer: Timer?
    private var isScanning = false
    private var logCycle = 0

    private let maxSamples = 30

    var stableLandmarks: [Landmark] {
        landmarks.values.filter { $0.isStable }
    }

    func start() {
        guard !isScanning else { return }
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            print("[Landmarks] Initializing CBCentralManager...")
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
        print("[Landmarks] Stopped scanning")
    }

    func currentFingerprint() -> [LandmarkSighting] {
        let fp = stableLandmarks.map { landmark in
            LandmarkSighting(landmarkID: landmark.id, rssi: Int(landmark.smoothedRSSI))
        }
        if !fp.isEmpty {
            print("[Landmarks] Fingerprint: \(fp.count) landmarks -> [\(fp.map { "\($0.landmarkID.prefix(8)):\($0.rssi)" }.joined(separator: ", "))]")
        }
        return fp
    }

    private func beginScanning() {
        guard let cm = centralManager, cm.state == .poweredOn else {
            print("[Landmarks] Cannot scan — BLE state: \(centralManager?.state.rawValue ?? -1)")
            return
        }

        cm.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        print("[Landmarks] Scanning ALL BLE devices for landmarks...")
    }

    private func cleanup() {
        logCycle += 1
        let cutoff = Date().addingTimeInterval(-60)
        let before = landmarks.count
        let removedNames = landmarks.filter { $0.value.lastSeen <= cutoff }.values.map { $0.localName ?? $0.id.prefix(8).description }
        landmarks = landmarks.filter { $0.value.lastSeen > cutoff }
        let removed = before - landmarks.count

        if removed > 0 {
            print("[Landmarks] Cleaned up \(removed): [\(removedNames.joined(separator: ", "))]")
        }

        landmarkCount = stableLandmarks.count
        logFullReport()
    }

    private func logFullReport() {
        let all = Array(landmarks.values)
        let stable = all.filter { $0.isStable }
        let unstable = all.filter { !$0.isStable }

        print("")
        print("[Landmarks] ╔══════════════════════════════════════════════════════════")
        print("[Landmarks] ║ REPORT #\(logCycle) — \(stable.count) stable / \(all.count) total / \(totalDevicesSeen) ever seen")
        print("[Landmarks] ╠══════════════════════════════════════════════════════════")

        if stable.isEmpty {
            print("[Landmarks] ║ No stable landmarks yet (need 15s+ of low-variance data)")
        } else {
            print("[Landmarks] ║ STABLE LANDMARKS (used for triangulation):")
            for lm in stable.sorted(by: { $0.smoothedRSSI > $1.smoothedRSSI }) {
                let name = (lm.localName ?? "unnamed").padding(toLength: 20, withPad: " ", startingAt: 0)
                let mfg = lm.manufacturerName.padding(toLength: 10, withPad: " ", startingAt: 0)
                let age = Int(Date().timeIntervalSince(lm.firstSeen))
                let dist = PositionEstimator.rssiToDistance(lm.smoothedRSSI)
                print("[Landmarks] ║  ✓ \(name) \(mfg) RSSI=\(String(format: "%3d", Int(lm.smoothedRSSI))) σ=\(String(format: "%.1f", lm.rssiVariance)) ~\(String(format: "%.1f", dist))m \(age)s \(lm.stabilityReason) [\(lm.id.prefix(8))]")
            }
        }

        if !unstable.isEmpty && logCycle % 3 == 0 { // show unstable every 3rd cycle to reduce noise
            print("[Landmarks] ╠──────────────────────────────────────────────────────────")
            print("[Landmarks] ║ UNSTABLE (not used — showing why):")
            for lm in unstable.sorted(by: { $0.smoothedRSSI > $1.smoothedRSSI }).prefix(10) {
                let name = (lm.localName ?? "unnamed").padding(toLength: 20, withPad: " ", startingAt: 0)
                let mfg = lm.manufacturerName.padding(toLength: 10, withPad: " ", startingAt: 0)
                let age = Int(Date().timeIntervalSince(lm.firstSeen))
                print("[Landmarks] ║  ✗ \(name) \(mfg) RSSI=\(String(format: "%3d", Int(lm.smoothedRSSI))) σ=\(String(format: "%.1f", lm.rssiVariance)) \(age)s \(lm.stabilityReason)")
            }
            if unstable.count > 10 {
                print("[Landmarks] ║  ... +\(unstable.count - 10) more unstable devices")
            }
        }

        print("[Landmarks] ╚══════════════════════════════════════════════════════════")
        print("")
    }

    private func stableID(peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        var components: [String] = []

        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
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

        if components.count >= 2 {
            let combined = components.joined(separator: "|")
            let digest = SHA256.hash(data: Data(combined.utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }

        return peripheral.identifier.uuidString
    }
}

// MARK: - CBCentralManagerDelegate

extension LandmarkTracker: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateNames = ["unknown", "resetting", "unsupported", "unauthorized", "poweredOff", "poweredOn"]
        let stateName = central.state.rawValue < stateNames.count ? stateNames[central.state.rawValue] : "?"
        print("[Landmarks] Bluetooth state: \(stateName) (\(central.state.rawValue))")

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
        guard rssi != 127 && rssi < 0 else { return }

        Task { @MainActor in
            let id = stableID(peripheral: peripheral, advertisementData: advertisementData)
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String

            var mfgID: UInt16?
            if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2 {
                mfgID = UInt16(mfg[0]) | (UInt16(mfg[1]) << 8)
            }

            // Skip Marco devices — they're contacts, not landmarks
            if let n = name, n.hasPrefix("MR-") { return }

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

                let mfgName = mfgID.flatMap { knownManufacturers[$0] } ?? mfgID.map { String(format: "0x%04X", $0) } ?? "???"
                print("[Landmarks] NEW #\(totalDevicesSeen): \(name ?? "unnamed") | \(mfgName) | RSSI=\(rssi) | id=\(id.prefix(12))")
            }

            landmarkCount = stableLandmarks.count
        }
    }
}
