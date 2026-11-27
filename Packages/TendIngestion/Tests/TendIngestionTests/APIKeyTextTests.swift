// PO ruling R28-F5: pasted provider keys are trimmed at both ends and refused unless every character is in
// U+0021…U+007E (AC-M2-21, AC-M2-23; review R28-F5). The rule, the in-memory store and the router. P-3, UX-3.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("R28-F5 pasted key text (AC-M2-21, AC-M2-23)")
struct APIKeyTextTests {
    static let core = "sk-test_AbC123xyz"

    static let trimmedCases: [String] = [
        "\n\(core)", "\(core)\n", "\r\n\(core)\r\n", "  \(core)  ", "\t\(core)\t", "\u{FEFF}\(core)",
        "\u{200B}\(core)\u{200C}", "\u{00A0}\(core)\u{2028}", "\u{2060}\(core)\u{200D}", "\u{0}\(core)\u{7F}",
        "\u{2029} \u{FEFF}\t\(core)\r\n\u{200B}",
    ]

    @Test("Edge whitespace, line breaks, control characters and the invisible marks are trimmed; the key reads back trimmed",
          arguments: trimmedCases)
    func trimmed(raw: String) {
        #expect(APIKeyText.cleaned(raw) == Self.core)
    }

    static let refusedCases: [String] = [
        "sk test", "sk\ntest", "sk\ttest", "sk\u{0}test", "sk\u{200B}test", "clé-123", "sk\u{7F}test",
        "", "   ", "\r\n\t", "\u{FEFF}\u{200B}", "\u{00A0}",
    ]

    @Test("A key with an inner space, line break, tab, NUL, U+200B, é or DEL, or empty after trimming, is refused",
          arguments: refusedCases)
    func refused(raw: String) {
        #expect(APIKeyText.cleaned(raw) == nil)
    }

    @Test("A key holding every character U+0021…U+007E is kept exactly; a one-character key is accepted")
    func printableASCII() {
        let all = String((0x21...0x7E).map { Character(Unicode.Scalar($0)!) })
        #expect(APIKeyText.cleaned(all) == all)
        #expect(APIKeyText.cleaned("a") == "a")
        #expect(APIKeyText.isSendable(APIKey(all)))
        #expect(!APIKeyText.isSendable(APIKey(" \(all)")))
        #expect(!APIKeyText.isSendable(APIKey("")))
    }

    /// A small seeded generator (SplitMix64) for the property test.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("Property (seed 0x5EED_F5): random edge padding around a random printable key reads back the original (2,000 keys)")
    func paddingProperty() {
        var rng = SplitMix(state: 0x5EED_F5)
        let junk: [Unicode.Scalar] = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{0}", "\u{7F}", "\u{85}",
                                      "\u{A0}", "\u{1680}", "\u{2000}", "\u{200A}", "\u{2028}", "\u{2029}",
                                      "\u{202F}", "\u{205F}", "\u{3000}", "\u{200B}", "\u{200C}", "\u{200D}",
                                      "\u{2060}", "\u{FEFF}", "\u{1B}"]
        var mismatches = 0
        for _ in 0..<2_000 {
            let length = Int.random(in: 1...64, using: &rng)
            let key = String((0..<length).map { _ in Character(Unicode.Scalar(UInt8.random(in: 0x21...0x7E,
                                                                                         using: &rng))) })
            func pad() -> String {
                String(String.UnicodeScalarView((0..<Int.random(in: 0...6, using: &rng)).map { _ in
                    junk[Int.random(in: 0..<junk.count, using: &rng)]
                }))
            }
            if APIKeyText.cleaned(pad() + key + pad()) != key { mismatches += 1 }
        }
        print("R28-F5 property: seed 0x5EED_F5, 2000 keys, \(mismatches) mismatches")
        #expect(mismatches == 0)
    }

    @Test("In-memory store: a padded key is stored trimmed; a refused key throws keyTextNotAccepted and keeps the earlier key")
    func inMemoryStore() async throws {
        let store = InMemoryAPIKeyStore()
        try await store.save(APIKey("\n \(Self.core)\r\n"), for: .openAI)
        #expect(await store.key(for: .openAI) == APIKey(Self.core))
        do {
            try await store.save(APIKey("sk new key"), for: .openAI)
            Issue.record("a key with an inner space was saved")
        } catch {
            #expect(error == .keyTextNotAccepted)
        }
        #expect(await store.key(for: .openAI) == APIKey(Self.core))
        do {
            try await store.save(APIKey("  \u{200B}"), for: .gemini)
            Issue.record("an empty key was saved")
        } catch {
            #expect(error == .keyTextNotAccepted)
        }
        #expect(await store.hasKey(for: .gemini) == false)
    }

    @Test("The refusal holds no character of the key and no position (sentinel)")
    func refusalNeutral() async {
        let sentinel = "SENTINEL9q7"
        let store = InMemoryAPIKeyStore()
        var thrown: CloudStoreError?
        do { try await store.save(APIKey("\(sentinel) é"), for: .anthropic) } catch { thrown = error }
        let error = thrown ?? .storeUnavailable
        #expect(error == .keyTextNotAccepted)
        var dumped = ""
        dump(error, to: &dumped)
        for text in [String(describing: error), String(reflecting: error), "\(error)", dumped] {
            #expect(!text.contains(sentinel))
            #expect(!text.contains("é"))
            #expect(text.rangeOfCharacter(from: .decimalDigits) == nil, "no position in \(text)")
        }
        // Foundation's generic text names only the type and its case number, never the key.
        #expect(!error.localizedDescription.contains(sentinel))
    }

    @Test("Router: turning cloud on with a refused key changes nothing (no consent, earlier key and consent kept)")
    func routerRefusal() async throws {
        let keys = InMemoryAPIKeyStore()
        let consents = InMemoryCloudConsentStore()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: RecordingTransport()),
                                 consents: consents, keys: keys)
        #expect(try await router.turnCloudOn(.openAI, key: APIKey(" \(Self.core)\n")) == .on(.openAI))
        #expect(await keys.key(for: .openAI) == APIKey(Self.core))
        do {
            _ = try await router.turnCloudOn(.openAI, key: APIKey("bad key"))
            Issue.record("a refused key turned cloud on")
        } catch {
            #expect(error == .keyTextNotAccepted)
        }
        #expect(await keys.key(for: .openAI) == APIKey(Self.core))
        #expect(await router.cloudStatus() == .on(.openAI))
        do {
            _ = try await router.turnCloudOn(.gemini, key: APIKey("é"))
            Issue.record("a refused key turned cloud on")
        } catch {
            #expect(error == .keyTextNotAccepted)
        }
        #expect(await consents.hasConsent(for: .gemini) == false)
        #expect(await keys.hasKey(for: .gemini) == false)
    }

    @Test("An auth header is sendable only for a key in U+0021…U+007E")
    func headerSendable() throws {
        let input = CloudPayloadInput(capture: "buy pods", roomNames: [], shortlistTitles: [])
        for provider in CloudProvider.allCases {
            let model = CloudModel.defaultModel(for: provider)
            let good = try CloudPayloadBuilder.request(input, model: model, key: APIKey(Self.core))
            let bad = try CloudPayloadBuilder.request(input, model: model, key: APIKey("sk bad"))
            let goodSendable = good.headers.allSatisfy { $0.keyIsSendable }
            let badSendable = bad.headers.allSatisfy { $0.keyIsSendable }
            let refusedAreAuth = bad.headers.filter { !$0.keyIsSendable }.allSatisfy { $0.isAuthorization }
            #expect(goodSendable)
            #expect(!badSendable)
            #expect(refusedAreAuth)
        }
    }
}
