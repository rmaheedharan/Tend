// The consent store and the key store (ADR-0005 Decisions 2 and 5; brief Definitions "Cloud model"; AC-M2-18). P-3,
// P-4.
//
// Both are protocols. The in-memory implementations here are for tests and previews. The real stores are:
// - the Keychain key store in `TendAI` (`KeychainAPIKeyStore.swift`, WI-M2-M5, owner-run Mac; AC-M2-21);
// - the durable consent store in M3, which must not be restorable from a backup or iCloud (Q21).
// The restore rule does not depend on them: cloud is on only when the selected provider has both a consent record and
// a key, and a key with no consent record is deleted (`ModelRouter`).

import Foundation

/// A provider API key the user pasted (ADR-0005 Decision 5). Its text is never shown: `description`,
/// `debugDescription` and reflection give a fixed placeholder, so the key cannot reach a log, an error message or a
/// `dump` through formatting (AC-M2-21). Only an adapter that builds the auth header reads the text, through
/// `withSecret`. The masked display form is WI-M2-M5's (AC-M2-21).
public struct APIKey: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let secret: String

    public init(_ secret: String) {
        self.secret = secret
    }

    /// Gives the key text to `body` only (for the provider's auth header).
    public func withSecret<Result>(_ body: (String) throws -> Result) rethrows -> Result {
        try body(secret)
    }

    public var description: String { "APIKey(hidden)" }
    public var debugDescription: String { "APIKey(hidden)" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Why a store could not do what was asked. Neutral: it describes the store, never the person (UX-3).
public enum CloudStoreError: Error, CaseIterable, Hashable, Sendable {
    /// The store cannot be read or written right now (for example, the device is locked).
    case notAccessibleNow
    /// The store is not working.
    case storeUnavailable
    /// The pasted key holds characters a provider key cannot hold, or nothing once trimmed (PO R28-F5,
    /// `APIKeyText`). Nothing was saved; any earlier key is kept. It holds no character of the key.
    case keyTextNotAccepted
}

/// Where the provider keys live: one key per provider (ADR-0005 Decision 5).
public protocol APIKeyStore: Sendable {
    /// Whether a key is stored for `provider`, without reading its text.
    func hasKey(for provider: CloudProvider) async throws(CloudStoreError) -> Bool
    /// The stored key, or nil.
    func key(for provider: CloudProvider) async throws(CloudStoreError) -> APIKey?
    /// Stores `key` for `provider`, trimmed by `APIKeyText.cleaned`, replacing any earlier key. A key that
    /// `APIKeyText` refuses is not saved (the earlier key is kept) and throws `keyTextNotAccepted`.
    func save(_ key: APIKey, for provider: CloudProvider) async throws(CloudStoreError)
    /// Deletes the key for `provider`. Deleting a key that is not there is not an error.
    func deleteKey(for provider: CloudProvider) async throws(CloudStoreError)
}

/// Where the consent records and the provider selection live (ADR-0005 Decision 2: consent is per provider; at most
/// one provider is selected).
public protocol CloudConsentStore: Sendable {
    func selectedProvider() async throws(CloudStoreError) -> CloudProvider?
    /// Selects `provider` (nil: none). At most one provider is selected.
    func select(_ provider: CloudProvider?) async throws(CloudStoreError)
    func hasConsent(for provider: CloudProvider) async throws(CloudStoreError) -> Bool
    func recordConsent(for provider: CloudProvider) async throws(CloudStoreError)
    /// Clears the consent record for `provider`. Clearing a record that is not there is not an error.
    func clearConsent(for provider: CloudProvider) async throws(CloudStoreError)
}

/// An in-memory key store (tests; never evidence for AC-M2-21). Starts empty, as on a fresh install.
public actor InMemoryAPIKeyStore: APIKeyStore {
    private var keys: [CloudProvider: APIKey]

    public init(keys: [CloudProvider: APIKey] = [:]) {
        self.keys = keys
    }

    public func hasKey(for provider: CloudProvider) -> Bool { keys[provider] != nil }
    public func key(for provider: CloudProvider) -> APIKey? { keys[provider] }
    public func save(_ key: APIKey, for provider: CloudProvider) throws(CloudStoreError) {
        guard let cleaned = APIKeyText.cleaned(key) else { throw .keyTextNotAccepted }
        keys[provider] = cleaned
    }
    public func deleteKey(for provider: CloudProvider) { keys[provider] = nil }
}

/// An in-memory consent store (tests). Starts with nothing selected and no consent, as on a fresh install.
public actor InMemoryCloudConsentStore: CloudConsentStore {
    private var selected: CloudProvider?
    private var consents: Set<CloudProvider>

    public init(selected: CloudProvider? = nil, consents: Set<CloudProvider> = []) {
        self.selected = selected
        self.consents = consents
    }

    public func selectedProvider() -> CloudProvider? { selected }
    public func select(_ provider: CloudProvider?) { selected = provider }
    public func hasConsent(for provider: CloudProvider) -> Bool { consents.contains(provider) }
    public func recordConsent(for provider: CloudProvider) { consents.insert(provider) }
    public func clearConsent(for provider: CloudProvider) { consents.remove(provider) }
}
