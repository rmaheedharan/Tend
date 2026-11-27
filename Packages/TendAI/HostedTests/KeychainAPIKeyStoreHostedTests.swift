// The Keychain key store in the iOS 26.5 Simulator, hosted by `TendAITestHost` (WI-M2-M5; brief AC-M2-21, AC-M2-18 (a)
// with the real Keychain; plan B5). P-3, P-4. A plain macOS `swift test` may fail with `errSecMissingEntitlement`, so
// these run only here. Each test uses its own Keychain service and deletes everything it made.

import Foundation
import Security
import Testing
import TendAI
import TendCore
import TendIngestion

/// Reads an item back as the Keychain stores it (independent of the store's own query).
enum KeychainProbe {
    static func attributes(service: String, account: String) -> (OSStatus, [String: Any]?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return (status, nil) }
        #expect(items.count == 1, "exactly one item for \(account)")
        return (status, items.first)
    }

    static func lookup(service: String, account: String) -> OSStatus {
        attributes(service: service, account: account).0
    }

    static func removeAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private func freshService() -> String { "tend.ai.key.test-\(UUID().uuidString)" }

@Suite("Keychain key store (WI-M2-M5; AC-M2-21, AC-M2-18 (a))", .serialized)
struct KeychainAPIKeyStoreHostedTests {

    static let longKey = "sk-test-0123456789abcdWXYZ"

    @Test("AC-M2-21: save, read, replace and delete, with the item's attributes read back from the Keychain",
          arguments: CloudProvider.allCases)
    func lifecycle(provider: CloudProvider) async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        #expect(try await store.hasKey(for: provider) == false)
        #expect(try await store.key(for: provider) == nil)

        try await store.save(APIKey(Self.longKey), for: provider)
        #expect(try await store.hasKey(for: provider))
        #expect(try await store.key(for: provider) == APIKey(Self.longKey))
        try Self.expectAttributes(service: service, provider: provider)

        try await store.save(APIKey("replacement-key-5678"), for: provider)
        #expect(try await store.key(for: provider) == APIKey("replacement-key-5678"))
        try Self.expectAttributes(service: service, provider: provider)

        try await store.deleteKey(for: provider)
        #expect(KeychainProbe.lookup(service: service, account: provider.rawValue) == errSecItemNotFound)
        #expect(try await store.hasKey(for: provider) == false)
        #expect(try await store.key(for: provider) == nil)
        // Deleting again is not an error.
        try await store.deleteKey(for: provider)
    }

    /// Generic password, when-unlocked-this-device-only, not synchronisable, exactly one item (T-16: read back, not
    /// the query sent).
    static func expectAttributes(service: String, provider: CloudProvider) throws {
        let (status, attributes) = KeychainProbe.attributes(service: service, account: provider.rawValue)
        #expect(status == errSecSuccess)
        let item = try #require(attributes)
        // The class is not among the returned attributes; the item is a generic password because the read-back above
        // searched only that class, and a search of the internet-password class for the same names finds nothing.
        let otherClass: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        #expect(SecItemCopyMatching(otherClass as CFDictionary, nil) == errSecItemNotFound)
        #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect((item[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false == false)
        #expect(item[kSecAttrService as String] as? String == service)
        #expect(item[kSecAttrAccount as String] as? String == provider.rawValue)
        // The data-protection keychain: the same item is found when the query asks for it explicitly.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        #expect(SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess)
    }

    @Test("Keys are kept per provider: saving or deleting one never touches another")
    func perProvider() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        for provider in CloudProvider.allCases { try await store.save(APIKey("key-for-\(provider.rawValue)"), for: provider) }
        try await store.deleteKey(for: .anthropic)
        #expect(try await store.key(for: .openAI) == APIKey("key-for-openAI"))
        #expect(try await store.key(for: .anthropic) == nil)
        #expect(try await store.key(for: .gemini) == APIKey("key-for-gemini"))
    }

    // Since PO ruling R28-F5 an empty or non-ASCII key is refused (`KeyPasteCleanupHostedTests`); length is still
    // never checked.
    @Test("A key of any length in U+0021…U+007E is stored and read back exactly (no length or prefix check)",
          arguments: ["a", "short-key", "sk-ant-api03-0123456789_abc", String(repeating: "x", count: 4_096)])
    func exactText(text: String) async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        try await store.save(APIKey(text), for: .gemini)
        #expect(try await store.key(for: .gemini) == APIKey(text))
    }

    @Test("AC-M2-18 (a) with the real Keychain: turning cloud off deletes the item")
    func turnOffDeletes() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let keys = KeychainAPIKeyStore(service: service)
        let router = ModelRouter(onDevice: UnavailableOnDevice(), cloudModels: NoCloudModels(),
                                 consents: InMemoryCloudConsentStore(), keys: keys)
        #expect(try await router.turnCloudOn(.openAI, key: APIKey(Self.longKey)) == .on(.openAI))
        #expect(KeychainProbe.lookup(service: service, account: CloudProvider.openAI.rawValue) == errSecSuccess)
        try await router.turnCloudOff()
        for provider in CloudProvider.allCases {
            #expect(KeychainProbe.lookup(service: service, account: provider.rawValue) == errSecItemNotFound)
        }
        #expect(await router.cloudStatus() == .off)
    }

    @Test("AC-M2-18 (a) with the real Keychain: removing the key deletes the item")
    func removeKeyDeletes() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let keys = KeychainAPIKeyStore(service: service)
        let router = ModelRouter(onDevice: UnavailableOnDevice(), cloudModels: NoCloudModels(),
                                 consents: InMemoryCloudConsentStore(), keys: keys)
        _ = try await router.turnCloudOn(.gemini, key: APIKey(Self.longKey))
        try await router.removeKey(for: .gemini)
        #expect(KeychainProbe.lookup(service: service, account: CloudProvider.gemini.rawValue) == errSecItemNotFound)
        #expect(await router.cloudStatus() == .off)
    }

    @Test("An orphan key restored without consent is deleted from the Keychain at the first route choice (T-14)")
    func orphanDeleted() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let keys = KeychainAPIKeyStore(service: service)
        try await keys.save(APIKey(Self.longKey), for: .anthropic)
        let router = ModelRouter(onDevice: UnavailableOnDevice(), cloudModels: NoCloudModels(),
                                 consents: InMemoryCloudConsentStore(selected: .anthropic), keys: keys)
        #expect(await router.route(preference: .onDeviceFirst) == .none)
        #expect(KeychainProbe.lookup(service: service, account: CloudProvider.anthropic.rawValue) == errSecItemNotFound)
    }

    @Test("AC-M2-21: no formatting of any key-holding value shows the key")
    func formatting() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        let key = APIKey(Self.longKey)
        try await store.save(key, for: .openAI)
        let read = try #require(try await store.key(for: .openAI))
        var dumped = ""
        dump(read, to: &dumped)
        var dumpedStore = ""
        dump(store, to: &dumpedStore)
        let texts = [String(describing: key), String(reflecting: key), "\(read)", dumped, dumpedStore,
                     String(describing: store), String(reflecting: store),
                     String(describing: Mirror(reflecting: read).children.map { "\($0.label ?? ""):\($0.value)" }),
                     String(describing: CloudStoreError.allCases), String(reflecting: CloudStoreError.notAccessibleNow),
                     APIKeyMask.masked(read)]
        for text in texts {
            #expect(!text.contains(Self.longKey))
            #expect(!text.contains("0123456789"))
        }
    }
}

/// An on-device source that is never available (routing tests only).
struct UnavailableOnDevice: OnDeviceModelSource {
    func availability() -> OnDeviceAvailability { .unavailable(.deviceNotEligible) }
    func model(household: Household) -> any IngestionModel { NeverModel() }
}

struct NoCloudModels: CloudModelSource {
    func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel { NeverModel() }
}

struct NeverModel: IngestionModel {
    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        AsyncThrowingStream { $0.finish(throwing: ModelStopReason.otherModelError) }
    }
}
