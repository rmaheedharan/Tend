// The cloud model source for routing (WI-M2-M6; `CloudModelSource`; ADR-0005 Decisions 1, 5, 6). P-2, P-3.
//
// `ModelRouter` asks it for the routed provider's model with the key it has just read for this request (after the
// consent check at request start). It builds the provider's `IngestionModel` over one transport (the HTTPS transport
// in the app) and one clock. It never builds a model for a provider other than the one asked for, and never gives a
// cloud model the duplicate Tool (AC-M2-24).

import Foundation
import TendIngestion

public struct CloudAdapters<C: Clock>: CloudModelSource where C.Duration == Duration {
    let transport: any CloudTransport
    let clock: C

    public init(transport: any CloudTransport, clock: C) {
        self.transport = transport
        self.clock = clock
    }

    public func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
        switch provider {
        case .openAI: OpenAIIngestionModel(key: key, transport: transport, clock: clock)
        case .anthropic: AnthropicIngestionModel(key: key, transport: transport, clock: clock)
        case .gemini: GeminiIngestionModel(key: key, transport: transport, clock: clock)
        }
    }
}

extension CloudAdapters where C == ContinuousClock {
    /// The app's cloud models: HTTPS to the provider (`CloudHTTPTransport`) on the continuous clock.
    public init() {
        self.init(transport: CloudHTTPTransport(), clock: ContinuousClock())
    }
}
