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

    /// Maps hash → contact info for quick lookup
    private(set) var hashToContact: [String: HashedContact] = [:]

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
            print("[Contacts] Access request failed: \(error)")
            isAuthorized = false
        }
    }

    func loadAndHashContacts() {
        hashToContact.removeAll()

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

                for phone in contact.phoneNumbers {
                    let number = phone.value.stringValue
                    let hash = CryptoUtils.hashPhoneNumber(number)
                    hashToContact[hash] = HashedContact(name: name, phoneNumber: number, email: nil)
                }

                for email in contact.emailAddresses {
                    let emailStr = email.value as String
                    let hash = CryptoUtils.hashEmail(emailStr)
                    hashToContact[hash] = HashedContact(name: name, phoneNumber: nil, email: emailStr)
                }
            }
        } catch {
            print("[Contacts] Failed to enumerate contacts: \(error)")
        }

        contactCount = contacts
        hashCount = hashToContact.count
        print("[Contacts] Loaded \(contacts) contacts, \(hashToContact.count) hashes")
    }

    func lookup(_ hash: String) -> HashedContact? {
        hashToContact[hash]
    }
}
