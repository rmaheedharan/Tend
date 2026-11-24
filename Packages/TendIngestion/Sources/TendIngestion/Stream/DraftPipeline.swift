// The draft pipeline for one capture (brief Definitions "Draft stream events"; AC-M2-05, AC-M2-10, AC-M2-23). FR-A1,
// P-1, P-3, P-4, UX-3.
//
// `events(from:)` returns an `AsyncSequence` whose `Failure` is `Never`: it never throws. It is lazy (the model is
// asked when iteration starts) and each iteration is a fresh parse. It holds exactly one routed model, so it never
// re-routes, never retries and queues nothing (the single cloud retry of AC-M2-22/23 lives in the cloud adapter's
// `CloudResponseBody`, WI-M2-14). It has no repository and writes nothing: commit (WI-M2-08) is the only write path,
// and takes confirmed drafts in ascending `draftID` (D6).
//
// Cancellation is cooperative (Swift structured concurrency). When the consuming task is cancelled, the next call to
// `next()` drops any buffered events, releases the model's stream (which ends the model's work through its
// termination handler) and returns `finished(.cancelled(route:))`; then `nil`. A model stream that ends while the
// task is cancelled is read as cancellation, never as a normal finish. No clock, timer or dispatch queue is used.

import Foundation
import TendCore

public struct DraftPipeline: Sendable {
    let mapper: DraftMapper
    let duplicateCheck: any DraftDuplicateCheck
    let request: IngestionRequest

    /// - Parameters:
    ///   - input: the finished text or final transcript (brief Definitions "Brain-dump input").
    ///   - rooms: the household's rooms, for linking (AC-M2-04); their names go to the model as written (Q19).
    ///   - now, calendar, timeZone: the injected time inputs (AC-M2-01).
    ///   - duplicateCheck: the duplicate rules for the route that will run: `DraftDuplicateRules.onDevice(household:)`
    ///     or `DraftDuplicateRules.cloud(_:capture:household:)` with this `input` as the capture (WI-M2-07). When it
    ///     is called is stated once, in the `DraftDuplicateCheck` documentation (at emission, and again after updates,
    ///     PO WI-M2-06 ruling 5).
    public init(input: String, rooms: [Room], now: Date, calendar: Calendar, timeZone: TimeZone,
                duplicateCheck: any DraftDuplicateCheck) {
        self.mapper = DraftMapper(input: input, rooms: rooms, now: now, calendar: calendar, timeZone: timeZone)
        self.duplicateCheck = duplicateCheck
        // The cloud titles come from the rules' own shortlist, so the titles sent and the claims accepted cannot
        // differ (WI-M2-10; `CloudContextSelector` gives the same values from the household).
        self.request = IngestionRequest(input: input, roomNames: rooms.map(\.name),
                                        shortlistTitles: duplicateCheck.sentShortlistTitles)
    }

    /// The draft stream for this capture on the routed model.
    public func events(from model: RoutedModel) -> DraftEventSequence {
        DraftEventSequence(pipeline: self, model: model)
    }
}

/// The draft stream events of one capture. Never throws; `finished` comes exactly once, last.
public struct DraftEventSequence: AsyncSequence, Sendable {
    public typealias Element = DraftStreamEvent
    public typealias Failure = Never

    let pipeline: DraftPipeline
    let model: RoutedModel

    public func makeAsyncIterator() -> Iterator {
        Iterator(
            assembler: DraftStreamAssembler(mapper: pipeline.mapper, duplicateCheck: pipeline.duplicateCheck,
                                            route: model.route),
            request: pipeline.request,
            source: .notStarted(model)
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = DraftStreamEvent
        public typealias Failure = Never

        enum Source {
            case notStarted(RoutedModel)
            case running(AsyncThrowingStream<IngestionSnapshot, any Error>.Iterator)
            case ended
        }

        var assembler: DraftStreamAssembler
        let request: IngestionRequest
        var source: Source
        /// Events decided but not yet returned, in order.
        var pending: [DraftStreamEvent] = []
        var pendingStart = 0
        /// `finished` has been returned; every later call returns nil.
        var isDone = false

        public mutating func next() async -> DraftStreamEvent? {
            await next(isolation: nil)
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async -> DraftStreamEvent? {
            while !isDone {
                if Task.isCancelled {
                    // Cancellation wins over anything not yet returned, including an undelivered outcome.
                    source = .ended
                    pending = []
                    pendingStart = 0
                    isDone = true
                    return .finished(.cancelled(route: assembler.route))
                }
                if pendingStart < pending.count {
                    let event = pending[pendingStart]
                    pendingStart += 1
                    if case .finished = event { isDone = true; source = .ended }
                    return event
                }
                pending = []
                pendingStart = 0
                await pull(isolation: actor)
            }
            return nil
        }

        /// Reads one step from the model (or starts it) and buffers the events it gives.
        private mutating func pull(isolation actor: isolated (any Actor)?) async {
            switch source {
            case let .notStarted(routed):
                switch routed {
                case let .none(reason):
                    source = .ended
                    pending = assembler.unavailable(reason)
                case let .onDevice(model), let .cloud(_, model):
                    source = .running(model.snapshots(for: request).makeAsyncIterator())
                }
            case var .running(iterator):
                do {
                    // A cancelled wait returns early (nil or a throw). Whatever it buffers here, the cancellation
                    // check at the top of `next` runs before any event is returned, so it is read as cancellation,
                    // never as a normal finish.
                    let snapshot = try await iterator.next(isolation: actor)
                    if let snapshot {
                        source = .running(iterator)
                        pending = assembler.receive(snapshot)
                    } else {
                        source = .ended
                        pending = assembler.finishNormally()
                    }
                } catch {
                    source = .ended
                    pending = assembler.stop(error)
                }
            case .ended:
                // Only reached if the assembler gave no `finished`, which it always does; end calmly.
                pending = assembler.cancel()
                if pending.isEmpty { isDone = true }
            }
        }
    }
}
