// One capture's cloud response body: the attempts over the neutral transport, the per-attempt timeouts from the
// deadline, and the single 429/5xx retry (plan WI-M2-14; brief AC-M2-22 "Timeouts", AC-M2-23; Q22, T-17, T-28). FR-A1,
// P-3, P-4, UX-3.
//
// The cloud adapter (`TendAI` `CloudIngestionModel`, WI-M2-M6) builds the request, creates this sequence with the
// instant the pipeline received the input (`start`), reads its chunks into the provider stream reader (WI-M2-13) and
// yields the snapshots. The iterator:
// - before each attempt, reads the injected clock; with no time left it sends nothing and throws `timedOut`;
//   otherwise it sends with `CloudTiming.timeouts(timeLeft:)`;
// - passes each body chunk on in order. A chunk or a normal end seen at or after the deadline is not read: it throws
//   `timedOut` (the transport's resource timeout should already have fired; this holds the deadline on the injected
//   clock too);
// - on a `CloudTransportFailure`, asks `CloudRetryRule` (429/5xx, first attempt, no body bytes yet, ≥ 3.0 s left after
//   the pause). With a pause it sleeps on the injected clock, checks the 3.0 s rule again with the clock's time after
//   the pause, and sends the same request once more. Otherwise it throws the failure's `ModelStopReason`;
// - maps any other error to `otherModelError` (adapter contract rule 1); `CancellationError` passes through, and a
//   read in an already cancelled task sends nothing (IngestionModel contract rule 3). A transport stream that ends
//   while the reading task is cancelled ends the body with `CancellationError`, never as a normal end (review R30-F1);
// - after it throws or ends, returns nil and sends nothing more. Nothing is queued, stored or retried in the
//   background (AC-M2-23, ADR-0005 Decision 7): when the iterator is released, the transport stream is released and
//   its termination handler cancels the network task.
// No `Date`, no ambient clock, no I/O, no logging: time and waiting come only from the injected `Clock`.

import Foundation

/// The response body of one capture's cloud request, with the deadline and the single retry; see the file header.
public struct CloudResponseBody<C: Clock>: AsyncSequence, Sendable where C.Duration == Duration {
    public typealias Element = [UInt8]
    public typealias Failure = any Error

    public let request: CloudRequest
    let transport: any CloudTransport
    let clock: C
    /// The moment the pipeline received the input.
    public let start: C.Instant

    public init(request: CloudRequest, transport: any CloudTransport, clock: C, start: C.Instant) {
        self.request = request
        self.transport = transport
        self.clock = clock
        self.start = start
    }

    /// The capture's cloud deadline: `start` + 10.0 s.
    public var deadline: C.Instant { start.advanced(by: CloudTiming.captureDeadline) }

    public func makeAsyncIterator() -> Iterator {
        Iterator(body: self)
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = [UInt8]
        public typealias Failure = any Error

        enum State {
            /// The next attempt (1-based) has not been sent yet.
            case beforeAttempt(Int)
            case reading(attempt: Int, AsyncThrowingStream<[UInt8], any Error>.Iterator, bodyStarted: Bool)
            case ended
        }

        let body: CloudResponseBody
        var state: State = .beforeAttempt(1)

        init(body: CloudResponseBody) {
            self.body = body
        }

        public mutating func next() async throws -> [UInt8]? {
            try await next(isolation: nil)
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async throws -> [UInt8]? {
            do {
                return try await step(isolation: actor)
            } catch {
                state = .ended
                throw error
            }
        }

        private var timeLeft: Duration { Self.timeLeft(body) }

        private static func timeLeft(_ body: CloudResponseBody) -> Duration {
            body.clock.now.duration(to: body.deadline)
        }

        private mutating func step(isolation actor: isolated (any Actor)?) async throws -> [UInt8]? {
            while true {
                switch state {
                case .ended:
                    return nil
                case let .beforeAttempt(attempt):
                    try Task.checkCancellation()
                    let left = timeLeft
                    guard left > .zero else { throw ModelStopReason.timedOut }
                    let stream = body.transport.send(body.request, timeouts: CloudTiming.timeouts(timeLeft: left))
                    state = .reading(attempt: attempt, stream.makeAsyncIterator(), bodyStarted: false)
                case .reading(let attempt, var iterator, let bodyStarted):
                    let chunk: [UInt8]?
                    do {
                        chunk = try await iterator.next(isolation: actor)
                    } catch let failure as CloudTransportFailure {
                        state = .ended
                        try await Self.retry(body, after: failure, attempt: attempt, bodyStarted: bodyStarted)
                        state = .beforeAttempt(attempt + 1)
                        continue
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw ModelStopReason.otherModelError
                    }
                    // A transport stream ends with nil when the reading task is cancelled; that is never a normal end
                    // of the body (review R30-F1).
                    if chunk == nil { try Task.checkCancellation() }
                    guard timeLeft > .zero else { throw ModelStopReason.timedOut }
                    guard let chunk else {
                        state = .ended
                        return nil
                    }
                    state = .reading(attempt: attempt, iterator, bodyStarted: true)
                    return chunk
                }
            }
        }

        /// Returns when the one retry may start (after its pause); throws the failure's reason when it may not.
        private static func retry(_ body: CloudResponseBody, after failure: CloudTransportFailure, attempt: Int,
                                  bodyStarted: Bool) async throws {
            guard let pause = CloudRetryRule.pause(after: failure, attempt: attempt, bodyStarted: bodyStarted,
                                                   timeLeft: timeLeft(body)) else {
                throw failure.stopReason
            }
            try await body.clock.sleep(for: pause)
            guard timeLeft(body) >= CloudTiming.minimumTimeLeftForRetry else { throw failure.stopReason }
        }
    }
}
