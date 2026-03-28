import Foundation
import simd

struct RelativePosition {
    let estimatedDistance: Double
    let confidence: Double
    let sharedLandmarkCount: Int
    let method: String
    let uwbDistance: Float?      // centimeter-accurate if available
    let uwbDirection: simd_float3?  // unit vector toward peer if available
}

enum PositionEstimator {

    static let txPower: Double = -59
    static let pathLossExponent: Double = 2.5

    static func rssiToDistance(_ rssi: Double) -> Double {
        guard rssi < 0 else { return 0.1 }
        return pow(10, (txPower - rssi) / (10 * pathLossExponent))
    }

    // MARK: - Combined Estimate (UWB + Landmarks + RSSI)

    /// Produce the best possible position estimate by combining all available data
    static func combinedEstimate(
        myFingerprint: [LandmarkSighting],
        theirFingerprint: [LandmarkSighting],
        directRSSI: Int,
        uwbDistance: Float? = nil,
        uwbDirection: simd_float3? = nil
    ) -> RelativePosition {

        // Priority 1: UWB (centimeter accuracy)
        if let uwbDist = uwbDistance {
            return RelativePosition(
                estimatedDistance: Double(uwbDist),
                confidence: 0.99,
                sharedLandmarkCount: 0,
                method: "uwb",
                uwbDistance: uwbDist,
                uwbDirection: uwbDirection
            )
        }

        // Priority 2: Landmark trilateration
        if let landmarkResult = estimate(myFingerprint: myFingerprint, theirFingerprint: theirFingerprint) {
            // Blend with direct RSSI for stability
            let rssiDist = rssiToDistance(Double(directRSSI))

            // Weight landmark estimate more heavily (0.7) vs RSSI (0.3)
            // but only when confidence is high
            let landmarkWeight = landmarkResult.confidence * 0.7
            let rssiWeight = 1.0 - landmarkWeight
            let blended = landmarkResult.estimatedDistance * landmarkWeight + rssiDist * rssiWeight

            return RelativePosition(
                estimatedDistance: blended,
                confidence: landmarkResult.confidence,
                sharedLandmarkCount: landmarkResult.sharedLandmarkCount,
                method: "landmark+rssi",
                uwbDistance: nil,
                uwbDirection: nil
            )
        }

        // Priority 3: Raw RSSI only
        let rssiDist = rssiToDistance(Double(directRSSI))
        return RelativePosition(
            estimatedDistance: rssiDist,
            confidence: 0.15,
            sharedLandmarkCount: 0,
            method: "rssi-only",
            uwbDistance: nil,
            uwbDirection: nil
        )
    }

    // MARK: - Landmark-Only Estimate

    static func estimate(
        myFingerprint: [LandmarkSighting],
        theirFingerprint: [LandmarkSighting]
    ) -> RelativePosition? {
        let theirMap = Dictionary(uniqueKeysWithValues: theirFingerprint.map { ($0.landmarkID, $0.rssi) })

        var shared: [(myRSSI: Double, theirRSSI: Double, weight: Double)] = []
        for mine in myFingerprint {
            if let theirs = theirMap[mine.landmarkID] {
                let myRSSI = Double(mine.rssi)
                let theirRSSI = Double(theirs)

                // Weight by RSSI reliability:
                // - Stronger signals (closer landmarks) are more reliable
                // - Both phones seeing similar RSSI = landmark is equidistant = less useful
                // - Large RSSI difference = more positional information
                let avgRSSI = (myRSSI + theirRSSI) / 2.0
                let signalWeight = max(0.1, (avgRSSI + 100) / 60.0) // stronger = higher
                let diffWeight = max(0.2, abs(myRSSI - theirRSSI) / 20.0) // bigger diff = more info
                let weight = signalWeight * diffWeight

                shared.append((myRSSI: myRSSI, theirRSSI: theirRSSI, weight: weight))
            }
        }

        guard !shared.isEmpty else { return nil }

        // Log only periodically (caller handles throttling)

        switch shared.count {
        case 1:
            return estimateFromSingle(shared[0])
        case 2:
            return estimateFromPair(shared[0], shared[1])
        default:
            return estimateFromMultiple(shared)
        }
    }

    // MARK: - 1 shared landmark

    private static func estimateFromSingle(_ s: (myRSSI: Double, theirRSSI: Double, weight: Double)) -> RelativePosition {
        let myDist = rssiToDistance(s.myRSSI)
        let theirDist = rssiToDistance(s.theirRSSI)
        let estimated = abs(theirDist - myDist)

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            confidence: 0.2,
            sharedLandmarkCount: 1,
            method: "rssi-ratio",
            uwbDistance: nil,
            uwbDirection: nil
        )
    }

    // MARK: - 2 shared landmarks

    private static func estimateFromPair(
        _ a: (myRSSI: Double, theirRSSI: Double, weight: Double),
        _ b: (myRSSI: Double, theirRSSI: Double, weight: Double)
    ) -> RelativePosition {
        let estA = abs(rssiToDistance(a.theirRSSI) - rssiToDistance(a.myRSSI))
        let estB = abs(rssiToDistance(b.theirRSSI) - rssiToDistance(b.myRSSI))

        let totalWeight = a.weight + b.weight
        let estimated = (estA * a.weight + estB * b.weight) / totalWeight

        return RelativePosition(
            estimatedDistance: max(0.5, estimated),
            confidence: 0.4,
            sharedLandmarkCount: 2,
            method: "dual-rssi",
            uwbDistance: nil,
            uwbDirection: nil
        )
    }

    // MARK: - 3+ shared landmarks: iterative least-squares

    private static func estimateFromMultiple(
        _ samples: [(myRSSI: Double, theirRSSI: Double, weight: Double)]
    ) -> RelativePosition {
        // Place landmarks on a unit circle relative to us (position 0,0)
        // Each landmark has: our distance to it (myDist) and their distance to it (theirDist)
        // We solve for their position (x, y) using weighted least squares

        let count = samples.count

        // Arrange landmarks at evenly-spaced angles on a circle
        // (we don't know true positions, so this is an approximation)
        var landmarkPositions: [(x: Double, y: Double, myDist: Double, theirDist: Double, weight: Double)] = []

        for (i, s) in samples.enumerated() {
            let angle = 2.0 * .pi * Double(i) / Double(count)
            let myDist = rssiToDistance(s.myRSSI)
            let theirDist = rssiToDistance(s.theirRSSI)

            // Place landmark at distance myDist from origin (us) at this angle
            let lx = myDist * cos(angle)
            let ly = myDist * sin(angle)

            landmarkPositions.append((x: lx, y: ly, myDist: myDist, theirDist: theirDist, weight: s.weight))
        }

        // Iterative weighted least squares to find (tx, ty) — their position
        var tx = 0.0
        var ty = 0.0

        for _ in 0..<10 { // 10 iterations
            var gradX = 0.0
            var gradY = 0.0
            var totalW = 0.0

            for lm in landmarkPositions {
                let dx = tx - lm.x
                let dy = ty - lm.y
                let currentDist = sqrt(dx * dx + dy * dy)
                let targetDist = lm.theirDist

                guard currentDist > 0.01 else { continue }

                let error = currentDist - targetDist
                let w = lm.weight

                // Gradient descent step
                gradX += w * error * dx / currentDist
                gradY += w * error * dy / currentDist
                totalW += w
            }

            guard totalW > 0 else { break }

            let learningRate = 0.3
            tx -= learningRate * gradX / totalW
            ty -= learningRate * gradY / totalW
        }

        let estimatedDistance = sqrt(tx * tx + ty * ty)

        // Confidence: more landmarks + better signal weights = higher
        let totalWeight = samples.reduce(0.0) { $0 + $1.weight }
        let avgWeight = totalWeight / Double(count)
        let baseConfidence = min(1.0, Double(count) * 0.12)
        let weightBonus = min(0.3, avgWeight * 0.15)
        let confidence = min(0.95, baseConfidence + weightBonus)

        // Compute residual error for quality assessment
        var totalResidual = 0.0
        for lm in landmarkPositions {
            let dx = tx - lm.x
            let dy = lm.y - ty
            let dist = sqrt(dx * dx + dy * dy)
            totalResidual += abs(dist - lm.theirDist) * lm.weight
        }
        let avgResidual = totalResidual / totalWeight

        return RelativePosition(
            estimatedDistance: max(0.5, estimatedDistance),
            confidence: confidence,
            sharedLandmarkCount: count,
            method: avgResidual < 3.0 ? "least-squares" : "least-squares(noisy)",
            uwbDistance: nil,
            uwbDirection: nil
        )
    }
}
