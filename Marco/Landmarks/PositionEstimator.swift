import Foundation

struct RelativePosition {
    let estimatedDistance: Double
    let confidence: Double // 0.0 to 1.0
    let sharedLandmarkCount: Int
    let method: String
}

enum PositionEstimator {

    static let txPower: Double = -50  // typical BLE RSSI at 1 meter
    static let pathLossExponent: Double = 2.5  // indoor environment

    /// Convert RSSI to distance in meters
    static func rssiToDistance(_ rssi: Double) -> Double {
        guard rssi < 0 else { return 0.1 }
        return pow(10, (txPower - rssi) / (10 * pathLossExponent))
    }

    /// Estimate relative position from two landmark fingerprints
    static func estimate(
        myFingerprint: [LandmarkSighting],
        theirFingerprint: [LandmarkSighting]
    ) -> RelativePosition? {
        print("[Position] Comparing fingerprints: mine=\(myFingerprint.count) theirs=\(theirFingerprint.count)")

        let theirMap = Dictionary(uniqueKeysWithValues: theirFingerprint.map { ($0.landmarkID, $0.rssi) })

        var shared: [(landmarkID: String, myRSSI: Double, theirRSSI: Double)] = []
        for mine in myFingerprint {
            if let theirs = theirMap[mine.landmarkID] {
                shared.append((landmarkID: mine.landmarkID, myRSSI: Double(mine.rssi), theirRSSI: Double(theirs)))
            }
        }

        if shared.isEmpty {
            print("[Position] No shared landmarks found")
            return nil
        }

        print("[Position] \(shared.count) shared landmarks:")
        for s in shared {
            let myDist = rssiToDistance(s.myRSSI)
            let theirDist = rssiToDistance(s.theirRSSI)
            print("[Position]   [\(s.landmarkID.prefix(8))] myRSSI=\(Int(s.myRSSI))→\(String(format: "%.1f", myDist))m theirRSSI=\(Int(s.theirRSSI))→\(String(format: "%.1f", theirDist))m Δ=\(String(format: "%.1f", abs(theirDist - myDist)))m")
        }

        let pairs = shared.map { (myRSSI: $0.myRSSI, theirRSSI: $0.theirRSSI) }

        let result: RelativePosition
        switch pairs.count {
        case 1:
            result = estimateFromSingle(pairs[0])
        case 2:
            result = estimateFromPair(pairs[0], pairs[1])
        default:
            result = estimateFromMultiple(pairs)
        }

        print("[Position] Result: \(String(format: "%.1f", result.estimatedDistance))m confidence=\(String(format: "%.0f", result.confidence * 100))% method=\(result.method)")
        return result
    }

    // MARK: - 1 shared landmark: basic distance ratio

    private static func estimateFromSingle(_ pair: (myRSSI: Double, theirRSSI: Double)) -> RelativePosition {
        let myDist = rssiToDistance(pair.myRSSI)
        let theirDist = rssiToDistance(pair.theirRSSI)

        // Triangle inequality: they're between |myDist - theirDist| and myDist + theirDist from us
        // Best estimate: use the difference
        let estimated = abs(theirDist - myDist)

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            confidence: 0.2,
            sharedLandmarkCount: 1,
            method: "rssi-ratio"
        )
    }

    // MARK: - 2 shared landmarks: distance range

    private static func estimateFromPair(
        _ a: (myRSSI: Double, theirRSSI: Double),
        _ b: (myRSSI: Double, theirRSSI: Double)
    ) -> RelativePosition {
        let myDistA = rssiToDistance(a.myRSSI)
        let theirDistA = rssiToDistance(a.theirRSSI)
        let myDistB = rssiToDistance(b.myRSSI)
        let theirDistB = rssiToDistance(b.theirRSSI)

        let estA = abs(theirDistA - myDistA)
        let estB = abs(theirDistB - myDistB)

        // Average the two estimates
        let estimated = (estA + estB) / 2.0

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            confidence: 0.4,
            sharedLandmarkCount: 2,
            method: "dual-rssi"
        )
    }

    // MARK: - 3+ shared landmarks: weighted trilateration

    private static func estimateFromMultiple(
        _ pairs: [(myRSSI: Double, theirRSSI: Double)]
    ) -> RelativePosition {
        // For each landmark, compute distance difference
        var distanceEstimates: [(estimate: Double, weight: Double)] = []

        for pair in pairs {
            let myDist = rssiToDistance(pair.myRSSI)
            let theirDist = rssiToDistance(pair.theirRSSI)
            let diff = abs(theirDist - myDist)

            // Weight by signal strength (stronger signals = more reliable)
            let avgRSSI = (pair.myRSSI + pair.theirRSSI) / 2.0
            let weight = max(0.1, 1.0 - (abs(avgRSSI) - 40) / 60.0) // closer = higher weight

            distanceEstimates.append((estimate: diff, weight: weight))
        }

        // Weighted average
        let totalWeight = distanceEstimates.reduce(0) { $0 + $1.weight }
        let weightedSum = distanceEstimates.reduce(0) { $0 + $1.estimate * $1.weight }
        let estimated = weightedSum / totalWeight

        // Confidence increases with more landmarks and stronger signals
        let baseConfidence = min(1.0, Double(pairs.count) * 0.15)
        let signalBonus = totalWeight / Double(pairs.count) * 0.3
        let confidence = min(0.95, baseConfidence + signalBonus)

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            confidence: confidence,
            sharedLandmarkCount: pairs.count,
            method: "trilateration"
        )
    }
}
