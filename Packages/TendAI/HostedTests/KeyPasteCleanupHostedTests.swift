// PO ruling R28-F5 with the real Keychain (iOS 26.5 Simulator host), and review PR #45 m1 (mutant K2) and n2.
// AC-M2-21, AC-M2-23. P-3, UX-3. Each test uses its own Keychain service and removes everything it made.

import Foundation
import Security
import Testing
import TendAI
import TendIngestion

private func freshService() -> String { "tend.ai.key.paste-\(UUID().uuidString)" }

/// Reads or plants raw items, independent of the store.
enum RawKeychain {
    static func data(service: String, account: String, synchronizable: Bool) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func plant(_ data: Data, service: String, account: String, synchronizable: Bool) -> OSStatus {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil)
    }
}

@Suite("R28-F5 pasted keys with the real Keychain; review PR #45 m1, n2", .serialized)
struct KeyPasteCleanupHostedTests {
    static let core = "sk-test_AbC123xyzWXYZ"

    @Test("A padded key is stored trimmed (the item's bytes are the trimmed key) and its mask is from the trimmed key",
          arguments: ["\n\(core)", "\(core)\r\n", "  \(core)\t", "\u{FEFF}\(core)\u{200B}", "\u{00A0}\(core)\u{2028}"])
    func storedTrimmed(raw: String) async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        try await store.save(APIKey(raw), for: .openAI)
        #expect(try await store.key(for: .openAI) == APIKey(Self.core))
        #expect(RawKeychain.data(service: service, account: "openAI", synchronizable: false) == Data(Self.core.utf8))
        #expect(APIKeyMask.masked(APIKey(raw)) == APIKeyMask.dots + "WXYZ")
    }

    @Test("A refused key is not saved, the earlier item is kept byte for byte, and the result is keyTextNotAccepted",
          arguments: ["sk new key", "sk\nnew", "clé-1", "sk\u{0}x", "   ", ""])
    func refusedKeepsEarlier(raw: String) async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        try await store.save(APIKey(Self.core), for: .anthropic)
        var thrown: CloudStoreError?
        do { try await store.save(APIKey(raw), for: .anthropic) } catch { thrown = error }
        #expect(thrown == .keyTextNotAccepted)
        #expect(try await store.key(for: .anthropic) == APIKey(Self.core))
        #expect(RawKeychain.data(service: service, account: "anthropic", synchronizable: false)
                == Data(Self.core.utf8))
        // Refused with nothing stored before: still nothing.
        var second: CloudStoreError?
        do { try await store.save(APIKey(raw), for: .gemini) } catch { second = error }
        #expect(second == .keyTextNotAccepted)
        #expect(KeychainProbe.lookup(service: service, account: "gemini") == errSecItemNotFound)
    }

    @Test("A short key is accepted; a key of every character U+0021…U+007E is kept exactly")
    func acceptedKeys() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let store = KeychainAPIKeyStore(service: service)
        try await store.save(APIKey("a"), for: .openAI)
        #expect(try await store.key(for: .openAI) == APIKey("a"))
        let all = String((0x21...0x7E).map { Character(Unicode.Scalar($0)!) })
        try await store.save(APIKey(all), for: .gemini)
        #expect(try await store.key(for: .gemini) == APIKey(all))
    }

    @Test("PR #45 m1 (K2): a synchronizable item with the same names is never read, matched or replaced")
    func synchronizableItemIgnored() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let sentinel = Data("SYNC-SENTINEL-7Q".utf8)
        let planted = RawKeychain.plant(sentinel, service: service, account: "openAI", synchronizable: true)
        try #require(planted == errSecSuccess, "could not plant a synchronizable item: \(planted)")
        let store = KeychainAPIKeyStore(service: service)
        #expect(try await store.hasKey(for: .openAI) == false)
        #expect(try await store.key(for: .openAI) == nil)
        try await store.save(APIKey(Self.core), for: .openAI)
        #expect(RawKeychain.data(service: service, account: "openAI", synchronizable: true) == sentinel)
        #expect(RawKeychain.data(service: service, account: "openAI", synchronizable: false) == Data(Self.core.utf8))
        #expect(try await store.key(for: .openAI) == APIKey(Self.core))
        // Delete removes only the store's own item.
        try await store.deleteKey(for: .openAI)
        #expect(RawKeychain.data(service: service, account: "openAI", synchronizable: true) == sentinel)
        #expect(try await store.key(for: .openAI) == nil)
    }

    @Test("PR #45 n2: stored data that is not UTF-8 reads as storeUnavailable, never as a key")
    func notUTF8() async throws {
        let service = freshService()
        defer { KeychainProbe.removeAll(service: service) }
        let planted = RawKeychain.plant(Data([0xFF, 0xFE, 0x00, 0xC3]), service: service, account: "gemini",
                                        synchronizable: false)
        try #require(planted == errSecSuccess)
        let store = KeychainAPIKeyStore(service: service)
        #expect(try await store.hasKey(for: .gemini))
        var thrown: CloudStoreError?
        do { _ = try await store.key(for: .gemini) } catch { thrown = error }
        #expect(thrown == .storeUnavailable)
    }

    @Test("The neutral refusal never shows the key, in any formatting (AC-M2-21 key-holding types)")
    func refusalFormatting() async {
        let sentinel = "LEAK-SENTINEL-3K"
        let store = KeychainAPIKeyStore(service: freshService())
        var thrown: CloudStoreError?
        do { try await store.save(APIKey(sentinel + " é"), for: .openAI) } catch { thrown = error }
        let error = thrown ?? .storeUnavailable
        var dumped = ""
        dump(error, to: &dumped)
        for text in [String(describing: error), String(reflecting: error), dumped, error.localizedDescription,
                     String(describing: CloudStoreError.allCases)] {
            #expect(!text.contains(sentinel))
        }
    }
}
