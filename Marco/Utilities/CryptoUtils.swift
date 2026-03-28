import Foundation
import CryptoKit

enum CryptoUtils {

    /// Normalize a phone number by stripping all non-digit characters
    /// and removing leading country code "1" for US numbers
    static func normalizePhoneNumber(_ number: String) -> String {
        var digits = number.filter { $0.isNumber }
        // Remove leading "1" for US numbers if 11 digits
        if digits.count == 11 && digits.hasPrefix("1") {
            digits = String(digits.dropFirst())
        }
        return digits
    }

    /// Normalize an email address (lowercase, trim whitespace)
    static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Generate a short hash from an input string.
    /// Uses salted SHA256, truncated to `MarcoConstants.hashLength` bytes.
    /// Returns a hex string.
    static func shortHash(_ input: String) -> String {
        let salted = MarcoConstants.hashSalt + input
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest
            .prefix(MarcoConstants.hashLength)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Hash a phone number (normalize first, then hash)
    static func hashPhoneNumber(_ number: String) -> String {
        let normalized = normalizePhoneNumber(number)
        return shortHash(normalized)
    }

    /// Hash an email (normalize first, then hash)
    static func hashEmail(_ email: String) -> String {
        let normalized = normalizeEmail(email)
        return shortHash(normalized)
    }

}
