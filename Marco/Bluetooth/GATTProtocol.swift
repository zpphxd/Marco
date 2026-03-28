import Foundation
import CoreBluetooth

/// Marco GATT Protocol Definition
///
/// All Marco devices act as both Central (scanner) and Peripheral (advertiser).
/// Discovery happens via service UUID advertisement. Data exchange happens
/// via GATT characteristic reads/writes after connection.
///
/// Background operation uses Herald-style keepalive:
///   1. Device A writes empty data to Device B's signal characteristic
///   2. After ~8 seconds, Device B sends a notification on the same characteristic
///   3. The notification wakes Device A's suspended app via State Restoration
///   4. Device A reads hash/landmarks, then writes back to keep the cycle alive
///
enum MarcoGATT {

    // MARK: - Service

    /// Primary Marco service UUID — advertised by all Marco devices
    /// This survives iOS backgrounding (moved to overflow area)
    static let serviceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")

    // MARK: - Characteristics

    /// Contact hash (Read)
    /// Returns 6-byte salted SHA256 hash of the device owner's phone number
    /// 12 hex characters as UTF-8 string
    static let hashCharUUID = CBUUID(string: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")

    /// Landmark fingerprint (Read)
    /// Returns JSON-encoded [LandmarkSighting] array
    /// Contains stable BLE device IDs and their Kalman-filtered RSSI values
    static let landmarkCharUUID = CBUUID(string: "E2C56DB5-0002-48D2-B060-D0F5A71096E0")

    /// Signal / Keepalive (Write Without Response + Notify)
    /// Herald-style keepalive cycle:
    ///   - Write: peer writes empty data to signal "I'm here"
    ///   - Notify: after delay, send notification to wake peer's app
    /// This maintains the connection indefinitely in background
    static let signalCharUUID = CBUUID(string: "E2C56DB5-0003-48D2-B060-D0F5A71096E0")

    /// Mesh relay (Write Without Response + Notify)
    /// Carries MeshEnvelope JSON (SEARCH/FOUND messages)
    /// Each connected peer is a potential mesh relay node
    static let meshCharUUID = CBUUID(string: "E2C56DB5-0004-48D2-B060-D0F5A71096E0")

    /// UWB Discovery Token (Read)
    /// Returns raw NIDiscoveryToken data for Nearby Interaction
    /// Only available on iPhone 11+ (U1/U2 chip)
    static let uwbTokenCharUUID = CBUUID(string: "E2C56DB5-0005-48D2-B060-D0F5A71096E0")

    // MARK: - State Restoration Identifiers

    static let centralRestoreID = "marco-central"
    static let peripheralRestoreID = "marco-peripheral"

    // MARK: - Timing

    /// Delay before sending keepalive notification back (seconds)
    /// Herald uses 2s — fast enough that iOS doesn't fully suspend the peer.
    /// The full cycle is: write → 2s delay → notify → readRSSI → 2s delay → write again
    static let keepaliveDelay: TimeInterval = 2.0

    /// How often to read landmarks from connected peers (seconds)
    static let landmarkReadInterval: TimeInterval = 10.0

    /// Maximum GATT characteristic value size (bytes)
    /// iOS supports up to 512 bytes per ATT read
    static let maxCharacteristicSize = 512
}
