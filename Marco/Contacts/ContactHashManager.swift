import Foundation
import Contacts

struct HashedContact {
    let name: String
    let phoneNumber: String?
    let email: String?
}

@MainActor
class ContactHashManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var contactCount = 0
    @Published var hashCount = 0
    @Published var appleHashCount = 0

    /// Maps our custom hash → contact info (Active Mode)
    private(set) var hashToContact: [String: HashedContact] = [:]

    /// Maps Apple-style 3-byte hash → contact info (Passive AirDrop Mode)
    private(set) var applePhoneHashToContact: [String: HashedContact] = [:]
    private(set) var appleEmailHashToContact: [String: HashedContact] = [:]

    private let store = CNContactStore()

    func checkExistingAuthorization() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized || status == .limited {
            isAuthorized = true
            loadAndHashContacts()
        }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            isAuthorized = granted
            if granted {
                loadAndHashContacts()
            }
        } catch {
            print("[ContactHashManager] Access request failed: \(error)")
            isAuthorized = false
        }
    }

    func loadAndHashContacts() {
        hashToContact.removeAll()
        applePhoneHashToContact.removeAll()
        appleEmailHashToContact.removeAll()

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts = 0

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                contacts += 1
                let fullName = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                let name = fullName.isEmpty ? "Unknown" : fullName

                // Hash each phone number — both our format and Apple's
                for phone in contact.phoneNumbers {
                    let number = phone.value.stringValue
                    let info = HashedContact(name: name, phoneNumber: number, email: nil)

                    // Our custom hash (Active Mode)
                    let hash = CryptoUtils.hashPhoneNumber(number)
                    hashToContact[hash] = info

                    // Apple-style hash (Passive AirDrop Mode)
                    let appleHash = CryptoUtils.applePhoneHash(number)
                    applePhoneHashToContact[appleHash] = info
                }

                // Hash each email — both formats
                for email in contact.emailAddresses {
                    let emailStr = email.value as String
                    let info = HashedContact(name: name, phoneNumber: nil, email: emailStr)

                    // Our custom hash
                    let hash = CryptoUtils.hashEmail(emailStr)
                    hashToContact[hash] = info

                    // Apple-style hash
                    let appleHash = CryptoUtils.appleEmailHash(emailStr)
                    appleEmailHashToContact[appleHash] = info
                }
            }
        } catch {
            print("[ContactHashManager] Failed to enumerate contacts: \(error)")
        }

        contactCount = contacts
        hashCount = hashToContact.count
        appleHashCount = applePhoneHashToContact.count + appleEmailHashToContact.count
        print("[ContactHashManager] Loaded \(contacts) contacts, \(hashToContact.count) custom hashes, \(appleHashCount) Apple-style hashes")
    }

    /// Check if a discovered hash matches any contact (Active Mode)
    func lookup(_ hash: String) -> HashedContact? {
        hashToContact[hash]
    }

    /// Check if an Apple-style phone hash matches any contact (Passive Mode)
    func lookupApplePhone(_ hash: String) -> HashedContact? {
        applePhoneHashToContact[hash]
    }

    /// Check if an Apple-style email hash matches any contact (Passive Mode)
    func lookupAppleEmail(_ hash: String) -> HashedContact? {
        appleEmailHashToContact[hash]
    }
}
