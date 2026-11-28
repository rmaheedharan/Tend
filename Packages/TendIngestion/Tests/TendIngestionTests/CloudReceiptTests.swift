// Review R50-F1: the router takes the capture's receipt (the start of the 10.0 s cloud deadline) the moment the
// pipeline receives the input, before the route choice and before any consent or Keychain read, and builds the cloud
// model from that capture's own receipt (AC-M2-22 "Timeouts", Q22, T-17). The timing itself, on the adapters' clock,
// is tested in `TendAI` (`CloudAdapterTests.deadlineFromReceipt`).

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

/// One shared, ordered log of what the router asked for.
final class CallLog: Sendable {
    private let entries = Mutex<[String]>([])
    func add(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
}

/// A cloud model source that logs each receipt (numbered) and which receipt each model was built from.
final class LoggingCloudModels: CloudModelSource {
    let log: CallLog
    private let count = Mutex(0)
    init(log: CallLog) { self.log = log }

    struct Receipt: CloudCaptureReceipt {
        let number: Int
        let log: CallLog
        func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
            log.add("model from receipt \(number)")
            return MockCloudModel(provider: provider, key: key, transport: RecordingTransport())
        }
    }

    func receive() -> any CloudCaptureReceipt {
        let number = count.withLock { $0 += 1; return $0 }
        log.add("receive \(number)")
        return Receipt(number: number, log: log)
    }
}

/// A key store that logs every read.
actor LoggingKeyStore: APIKeyStore {
    let log: CallLog
    private let base = InMemoryAPIKeyStore()
    init(log: CallLog) { self.log = log }

    func hasKey(for provider: CloudProvider) async throws(CloudStoreError) -> Bool {
        log.add("hasKey")
        return await base.hasKey(for: provider)
    }
    func key(for provider: CloudProvider) async throws(CloudStoreError) -> APIKey? {
        log.add("key")
        return await base.key(for: provider)
    }
    func save(_ key: APIKey, for provider: CloudProvider) async throws(CloudStoreError) {
        try await base.save(key, for: provider)
    }
    func deleteKey(for provider: CloudProvider) async throws(CloudStoreError) {
        await base.deleteKey(for: provider)
    }
}

@Suite("R50-F1: the cloud deadline starts at receipt, before routing and the Keychain read (AC-M2-22, Q22)")
struct CloudReceiptTests {
    func capture(_ router: ModelRouter) async -> RoutedDraftEvents {
        await router.events(input: StreamFixtures.input, household: Household(tasks: [], rooms: []),
                            now: StreamFixtures.now, calendar: MappingFixtures.gregorian,
                            timeZone: MappingFixtures.zone("America/New_York"), titleSharing: .shortlistTitles,
                            preference: .onDeviceFirst)
    }

    @Test("the receipt is taken first; each capture's model is built from its own receipt, after the key read")
    func receiptFirst() async throws {
        let log = CallLog()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: LoggingCloudModels(log: log), consents: InMemoryCloudConsentStore(),
                                 keys: LoggingKeyStore(log: log))
        try await router.turnCloudOn(.anthropic, key: APIKey("FAKE-TEST-KEY-not-a-real-key-0000"))
        let before = log.all.count
        let first = await capture(router)
        let second = await capture(router)
        #expect(first.route == .cloud(.anthropic) && second.route == .cloud(.anthropic))
        for await _ in first {}
        for await _ in second {}
        let calls = Array(log.all.dropFirst(before))
        #expect(calls.first == "receive 1", "\(calls)")
        let receive2 = try #require(calls.firstIndex(of: "receive 2"))
        #expect(calls[1..<receive2].contains("hasKey"), "routing reads the stores after the receipt: \(calls)")
        #expect(!calls[..<receive2].contains("key"), "the first capture's key is read only when its stream is read")
        let models = calls.filter { $0.hasPrefix("model") }
        #expect(models == ["model from receipt 1", "model from receipt 2"], "\(calls)")
        for number in [1, 2] {
            let model = try #require(calls.firstIndex(of: "model from receipt \(number)"))
            #expect(calls[..<model].filter { $0 == "key" }.count == number, "the key is read before the model is built")
        }
    }

    @Test("an on-device capture also takes a receipt first and builds no cloud model")
    func onDeviceReceipt() async throws {
        let log = CallLog()
        let router = ModelRouter(onDevice: FixedOnDevice(.available), cloudModels: LoggingCloudModels(log: log),
                                 consents: InMemoryCloudConsentStore(), keys: LoggingKeyStore(log: log))
        let routed = await capture(router)
        #expect(routed.route == .onDevice)
        for await _ in routed {}
        #expect(log.all.first == "receive 1")
        #expect(!log.all.contains { $0.hasPrefix("model") })
    }
}
