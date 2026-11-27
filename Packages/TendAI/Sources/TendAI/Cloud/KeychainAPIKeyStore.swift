// The Keychain key store (WI-M2-M5; ADR-0005 Decision 5; brief AC-M2-21, AC-M2-18 (a)). P-3, P-4.
//
// One generic-password item per provider, in the data-protection keychain, readable only while the device is
// unlocked, on this device only, never synchronised (no iCloud Keychain, not restorable to another device):
// `kSecClassGenericPassword`, `kSecUseDataProtectionKeychain`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
// `kSecAttrSynchronizable = false`. The service is `tend.ai.key` and the account is the provider's name.
//
// Allowlist file 3 of the cloud adapter (AC-M2-09 Rule 3): the only file that imports `Security`. It holds no
// networking. The key's text is read only to build the item's data and back into an `APIKey`; it is never logged,
// formatted or put in an error (the errors are `CloudStoreError`, which hold no value). `hasKey` reads attributes only,
// never the key's data.
//
// Whether a pasted key with surrounding whitespace or a control character is trimmed or refused is a PO decision
// (review R28-F5, open); until it is made, the key is stored exactly as given, and the transport refuses a header value
// with a line break before sending (WI-M2-M4).

import Foundation
import Security
import TendIngestion

public actor KeychainAPIKeyStore: APIKeyStore {
    /// The Keychain service of every Tend provider key.
    public static let defaultService = "tend.ai.key"

    let service: String

    /// - Parameter service: the Keychain service (tests use their own, so they never touch the app's items).
    public init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    public func hasKey(for provider: CloudProvider) throws(CloudStoreError) -> Bool {
        var query = itemQuery(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw Self.error(status)
        }
    }

    public func key(for provider: CloudProvider) throws(CloudStoreError) -> APIKey? {
        var query = itemQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
                throw CloudStoreError.storeUnavailable
            }
            return APIKey(text)
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(status)
        }
    }

    public func save(_ key: APIKey, for provider: CloudProvider) throws(CloudStoreError) {
        let data = key.withSecret { Data($0.utf8) }
        // Replace in place when an item exists, so a failed replace never leaves the provider without its old key.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updated = SecItemUpdate(itemQuery(provider) as CFDictionary, update as CFDictionary)
        switch updated {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = itemQuery(provider)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw Self.error(added) }
        default:
            throw Self.error(updated)
        }
    }

    public func deleteKey(for provider: CloudProvider) throws(CloudStoreError) {
        let status = SecItemDelete(itemQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    /// The item's identity: class, service, account, data-protection keychain, not synchronised.
    func itemQuery(_ provider: CloudProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// A Keychain status as a neutral store error (it never holds the key or the status text).
    static func error(_ status: OSStatus) -> CloudStoreError {
        status == errSecInteractionNotAllowed ? .notAccessibleNow : .storeUnavailable
    }
}
