import Foundation
import CoreBluetooth

// MARK: - Radar Status

enum RadarStatus: String {
    case off = "Off"
    case scanning = "Scanning"
    case found = "Contact Found"
}

// MARK: - Distance Estimate

enum DistanceEstimate: String, CaseIterable {
    case veryClose = "Very close (< 2m)"
    case nearby = "Nearby (~5m)"
    case inRange = "In range (~10-15m)"
    case far = "Far (20m+)"
    case unknown = "Unknown"

    static func from(rssi: Int) -> DistanceEstimate {
        switch rssi {
        case -50...0: return .veryClose
        case -65...(-49): return .nearby
        case -80...(-64): return .inRange
        case ..<(-79): return .far
        default: return .unknown
        }
    }

    var color: String {
        switch self {
        case .veryClose: return "green"
        case .nearby: return "yellow"
        case .inRange: return "orange"
        case .far: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Nearby Contact

struct NearbyContact: Identifiable {
    let id: String
    var name: String
    var phoneNumber: String?
    var rssi: Int
    var distance: DistanceEstimate
    var firstSeen: Date
    var lastSeen: Date
    var rssiHistory: [Int]

    var trend: Trend {
        guard rssiHistory.count >= 6 else { return .stable }
        // Compare last 5 samples against the 5 before that
        let recent = Array(rssiHistory.suffix(5))
        let older = Array(rssiHistory.dropLast(5).suffix(5))
        guard !recent.isEmpty && !older.isEmpty else { return .stable }
        let recentAvg = recent.reduce(0, +) / recent.count
        let olderAvg = older.reduce(0, +) / older.count
        let diff = recentAvg - olderAvg
        // Higher threshold (8 dBm) to avoid noise-triggered flicker
        if diff > 8 { return .approaching }
        if diff < -8 { return .receding }
        return .stable
    }

    enum Trend: String {
        case approaching = "Getting closer"
        case receding = "Getting farther"
        case stable = "Stable"

        var symbol: String {
            switch self {
            case .approaching: return "arrow.down.circle.fill"
            case .receding: return "arrow.up.circle.fill"
            case .stable: return "circle.fill"
            }
        }
    }
}

// MARK: - Constants

enum MarcoConstants {
    static let serviceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
    static let hashPrefix = "MR-"
    static let staleTimeout: TimeInterval = 30
    static let hashSalt = "marco-v1"
    static let hashLength = 6
}
