// The Gemini cloud model (WI-M2-M6; brief AC-M2-24; ADR-0005; Q18, PO WI-M2-10 ruling 7). FR-A1, P-3.
//
// The provider's curated default model (`CloudModel.defaultModel(for: .gemini)`) over the neutral transport, read by
// the Gemini stream dialect (WI-M2-13). The five Q18 conditions live in the provider table's request profile for this
// model (pinned ID, structured streaming, fixed sampling, least reasoning; "current" is checked against the served
// model in the real recording) and are tested in `CloudAdapterTests`. No networking type and no Tool here.

import Foundation
import TendIngestion

public struct GeminiIngestionModel<C: Clock>: IngestionModel where C.Duration == Duration {
    let cloud: CloudIngestionModel<C>

    /// - Parameter start: when the pipeline received the input (the deadline start, AC-M2-22).
    public init(key: APIKey, transport: any CloudTransport, clock: C, start: C.Instant) {
        cloud = CloudIngestionModel(model: CloudModel.defaultModel(for: .gemini), key: key, transport: transport,
                                    clock: clock, start: start)
    }

    public var model: CloudModel { cloud.model }

    public func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        cloud.snapshots(for: request)
    }
}
