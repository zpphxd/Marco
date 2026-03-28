import Foundation
import NearbyInteraction
import CoreBluetooth

/// Manages Ultra-Wideband sessions for centimeter-accurate distance
/// and direction finding on iPhone 11+ (U1/U2 chip).
///
/// Flow:
/// 1. Create NISession → get local NIDiscoveryToken
/// 2. Serve token via GATT uwbToken characteristic
/// 3. Receive peer's token via GATT read
/// 4. Create NINearbyPeerConfiguration with peer token
/// 5. Run session → receive continuous distance + direction updates
@MainActor
class UWBManager: NSObject, ObservableObject {
    @Published var isSupported = false
    @Published var isRunning = false
    @Published var peerDistance: Float?           // meters, centimeter accuracy
    @Published var peerDirection: simd_float3?    // unit vector pointing toward peer
    @Published var hasDirection = false           // false if device doesn't support direction

    private var session: NISession?
    private var myToken: NIDiscoveryToken?

    /// Called when we have a peer token to start the session
    var onTokenReady: ((Data) -> Void)?

    override init() {
        super.init()
        isSupported = NISession.isSupported
        if isSupported {
            setupSession()
        } else {
            print("[UWB] Not supported on this device")
        }
    }

    private func setupSession() {
        session = NISession()
        session?.delegate = self
        myToken = session?.discoveryToken
        if let token = myToken {
            print("[UWB] Session created, token ready (\(token.hashValue))")
        } else {
            print("[UWB] Session created but no token available")
        }
    }

    /// Get our discovery token as Data for GATT exchange
    func getTokenData() -> Data? {
        guard let token = myToken else { return nil }
        do {
            return try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        } catch {
            print("[UWB] Failed to archive token: \(error)")
            return nil
        }
    }

    /// Start a UWB session with a peer's token received via GATT
    func startSession(withPeerTokenData data: Data) {
        guard isSupported else {
            print("[UWB] Cannot start — not supported")
            return
        }

        do {
            guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: data
            ) else {
                print("[UWB] Failed to unarchive peer token")
                return
            }

            let config = NINearbyPeerConfiguration(peerToken: peerToken)
            session?.run(config)
            isRunning = true
            print("[UWB] Session started with peer")
        } catch {
            print("[UWB] Failed to start session: \(error)")
        }
    }

    func stop() {
        session?.pause()
        isRunning = false
        peerDistance = nil
        peerDirection = nil
        print("[UWB] Session stopped")
    }

    /// Restart the session (e.g., after suspension)
    func restart() {
        session?.invalidate()
        setupSession()
    }
}

// MARK: - NISessionDelegate

extension UWBManager: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }

        Task { @MainActor in
            peerDistance = object.distance

            if let direction = object.direction {
                peerDirection = direction
                hasDirection = true
            }

            let distStr = object.distance.map { String(format: "%.2fm", $0) } ?? "nil"
            let dirStr: String
            if let d = object.direction {
                dirStr = String(format: "(%.2f, %.2f, %.2f)", d.x, d.y, d.z)
            } else {
                dirStr = "no direction"
            }

            // Log every 10th update to avoid spam
            print("[UWB] distance=\(distStr) direction=\(dirStr)")
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            peerDistance = nil
            peerDirection = nil
            isRunning = false

            switch reason {
            case .peerEnded:
                print("[UWB] Peer ended session")
            case .timeout:
                print("[UWB] Session timed out")
            @unknown default:
                print("[UWB] Peer removed: unknown reason")
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        print("[UWB] Session suspended")
        Task { @MainActor in
            isRunning = false
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        print("[UWB] Suspension ended — restarting")
        Task { @MainActor in
            restart()
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        print("[UWB] Session invalidated: \(error.localizedDescription)")
        Task { @MainActor in
            isRunning = false
            restart()
        }
    }
}
