// The cloud model source for routing (WI-M2-M6; `CloudModelSource`; ADR-0005 Decisions 1, 5, 6). P-2, P-3.
//
// `ModelRouter` calls `receive()` the moment the pipeline receives a capture, before the route choice and before the
// consent and Keychain reads; the receipt reads the deadline start then, on the injected clock (AC-M2-22, Q22; review
// R50-F1). At request start the router asks the receipt for the routed provider's model with the key it has just
// read. The model is built over one transport (the HTTPS transport in the app) and the same clock. It never builds a
// model for a provider other than the one asked for, and never gives a cloud model the duplicate Tool (AC-M2-24).

import Foundation
import TendIngestion

public struct CloudAdapters<C: Clock>: CloudModelSource where C.Duration == Duration {
    let transport: any CloudTransport
    let clock: C

    public init(transport: any CloudTransport, clock: C) {
        self.transport = transport
        self.clock = clock
    }

    public func receive() -> any CloudCaptureReceipt {
        Receipt(transport: transport, clock: clock, start: clock.now)
    }

    /// One received capture: the deadline start, read once at receipt.
    struct Receipt: CloudCaptureReceipt {
        let transport: any CloudTransport
        let clock: C
        let start: C.Instant

        func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
            switch provider {
            case .openAI: OpenAIIngestionModel(key: key, transport: transport, clock: clock, start: start)
            case .anthropic: AnthropicIngestionModel(key: key, transport: transport, clock: clock, start: start)
            case .gemini: GeminiIngestionModel(key: key, transport: transport, clock: clock, start: start)
            }
        }
    }
}

extension CloudAdapters where C == ContinuousClock {
    /// The app's cloud models: HTTPS to the provider (`CloudHTTPTransport`) on the continuous clock.
    public init() {
        self.init(transport: CloudHTTPTransport(), clock: ContinuousClock())
    }
}
