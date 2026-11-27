// The cloud `IngestionModel`: one capture's request over the neutral transport, read by the provider's stream reader
// (WI-M2-M6; brief AC-M2-24, AC-M2-22, AC-M2-23; ADR-0005; `IngestionModel` adapter contract items 1-3). FR-A1, P-2,
// P-3, P-4.
//
// - **Same contract as the on-device model.** It yields the snapshots of `ProviderStreamReader` (WI-M2-13) and ends
//   by finishing normally or by throwing a `ModelStopReason`, so cloud drafts reach the draft stream exactly like
//   on-device ones (AC-M2-24).
// - **The request** is the payload builder's (WI-M2-10) for this capture, built only from the `IngestionRequest`
//   (the capture, the room names and, under Q12 = yes, the shortlist titles; ADR-0005 Decision 3) with the curated
//   model of the provider (Q18). The key is read only into the auth header.
// - **The body** is read through `CloudResponseBody` (WI-M2-14): the 10.0 s deadline on the injected clock from the
//   moment the capture reached this model, per-attempt timeouts and the single 429/5xx retry.
// - **No Tool.** A cloud model is never given the duplicate-lookup `Tool` (AC-M2-24): this type has none, and its
//   snapshots carry no lookup queries.
// - **Cancellation (contract 3).** A stream created in a cancelled task sends nothing; `onTermination` cancels the
//   reading task, which releases the transport stream and so cancels the network task.
// No networking type appears here (Rule 2): the transport is the neutral `CloudTransport`.

import Foundation
import TendCore
import TendIngestion

/// One provider's cloud model for one capture.
public struct CloudIngestionModel<C: Clock>: IngestionModel where C.Duration == Duration {
    /// The curated model (Q18); its provider is the routed provider.
    public let model: CloudModel
    let key: APIKey
    let transport: any CloudTransport
    let clock: C

    public init(model: CloudModel, key: APIKey, transport: any CloudTransport, clock: C) {
        self.model = model
        self.key = key
        self.transport = transport
        self.clock = clock
    }

    public var provider: CloudProvider { model.provider }

    public func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let (model, key, transport, clock) = (model, key, transport, clock)
        return AsyncThrowingStream { continuation in
            // Contract 3: created inside a cancelled task, it builds and sends nothing.
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            let start = clock.now
            let cloudRequest: CloudRequest
            do {
                cloudRequest = try CloudPayloadBuilder.request(CloudPayloadInput(request), model: model, key: key)
            } catch {
                // Unreachable in practice: the shortlist is capped at 10 titles before it reaches the request.
                continuation.finish(throwing: ModelStopReason.otherModelError)
                return
            }
            let task = Task {
                var reader = ProviderStreamReader(provider: model.provider)
                do {
                    for try await chunk in CloudResponseBody(request: cloudRequest, transport: transport, clock: clock,
                                                             start: start) {
                        if let snapshot = try reader.append(chunk) { continuation.yield(snapshot) }
                    }
                    continuation.yield(try reader.finish())
                    continuation.finish()
                } catch let error as ProviderStreamError {
                    continuation.finish(throwing: error.stopReason)
                } catch let reason as ModelStopReason {
                    continuation.finish(throwing: reason)
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: ModelStopReason.otherModelError)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
