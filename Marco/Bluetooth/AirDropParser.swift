import Foundation
import CoreBluetooth

// AirDrop passive scanning — stretch goal
// Based on published research by TU Darmstadt (OpenDrop / Apple BLE Continuity)
//
// AirDrop uses Apple's Continuity protocol over BLE.
// When AirDrop is enabled, devices advertise using manufacturer-specific data
// with Apple's company ID (0x004C).
//
// The advertisement contains truncated SHA256 hashes of:
// - Phone number (first 3 bytes of hash)
// - Apple ID email (first 3 bytes of hash)
//
// Reference: https://github.com/seemoo-lab/opendrop
// Paper: "A Billion Open Interfaces for Eve and Mallory"

enum AirDropParser {

    // Apple's BLE manufacturer ID
    static let appleCompanyID: UInt16 = 0x004C

    // AirDrop continuity type byte
    static let airDropType: UInt8 = 0x05

    /// Attempt to parse AirDrop contact hashes from raw advertisement data.
    /// Returns phone hash and email hash if found (3 bytes each, as hex strings).
    static func parse(advertisementData: [String: Any]) -> (phoneHash: String?, emailHash: String?)? {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return nil
        }

        // Apple manufacturer data starts with company ID (2 bytes, little-endian)
        // Followed by continuity message type and length
        guard manufacturerData.count >= 4 else { return nil }

        // Check for AirDrop continuity type
        // Format: [company_id_lo, company_id_hi, type, length, ...data...]
        let type = manufacturerData[2]
        guard type == airDropType else { return nil }

        // The exact byte offsets for contact hashes depend on the AirDrop version
        // and advertisement subtype. This is a simplified parser.
        // Full details in the OpenDrop research.

        // Typical AirDrop advertisement structure (after company ID):
        // Byte 2: Type (0x05 for AirDrop)
        // Byte 3: Length
        // Bytes 4-5: Status/flags
        // Bytes 6-8: Phone number hash (first 3 bytes of SHA256)
        // Bytes 9-11: Email hash (first 3 bytes of SHA256)
        // Bytes 12-14: Email2 hash (optional)

        guard manufacturerData.count >= 12 else { return nil }

        let phoneHashBytes = manufacturerData[6..<9]
        let emailHashBytes = manufacturerData[9..<12]

        let phoneHash = phoneHashBytes.map { String(format: "%02x", $0) }.joined()
        let emailHash = emailHashBytes.map { String(format: "%02x", $0) }.joined()

        // Filter out zero hashes (no contact info shared)
        let phone = phoneHash == "000000" ? nil : phoneHash
        let email = emailHash == "000000" ? nil : emailHash

        return (phoneHash: phone, emailHash: email)
    }
}
