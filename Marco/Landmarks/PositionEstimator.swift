import Foundation

struct RelativePosition {
    let estimatedDistance: Double
    let bearing: Double?
    let confidence: Double
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
        // Build lookup for their fingerprint
        let theirMap = Dictionary(uniqueKeysWithValues: theirFingerprint.map { ($0.landmarkID, $0.rssi) })

        // Find shared landmarks
        var shared: [(myRSSI: Double, theirRSSI: Double)] = []
        for mine in myFingerprint {
            if let theirs = theirMap[mine.landmarkID] {
                shared.append((myRSSI: Double(mine.rssi), theirRSSI: Double(theirs)))
            }
        }

        guard !shared.isEmpty else { return nil }

        switch shared.count {
        case 1:
            return estimateFromSingle(shared[0])
        case 2:
            return estimateFromPair(shared[0], shared[1])
        default:
            return estimateFromMultiple(shared)
        }
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
            bearing: nil,
            confidence: 0.2, // low confidence with 1 landmark
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
            bearing: nil,
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

        // Attempt bearing estimation from RSSI gradient
        // If landmarks on one side show stronger signal for them,
        // they're likely in that direction
        var bearing: Double?
        if pairs.count >= 3 {
            // Simple: find the landmark where they have strongest relative signal
            // This gives a rough direction
            var bestIdx = 0
            var bestDiff = -999.0
            for (i, pair) in pairs.enumerated() {
                let diff = pair.theirRSSI - pair.myRSSI // positive = they're closer to this landmark
                if diff > bestDiff {
                    bestDiff = diff
                    bestIdx = i
                }
            }

            // Use landmark index as a rough angle (evenly distributed assumption)
            // This is very approximate but gives SOME directional info
            bearing = Double(bestIdx) / Double(pairs.count) * 360.0
        }

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            bearing: bearing,
            confidence: confidence,
            sharedLandmarkCount: pairs.count,
            method: "trilateration"
        )
    }
}
