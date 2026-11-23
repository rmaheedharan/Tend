// The draft stream of one routed capture (AC-M2-18 (c), (d); AC-M2-19 "the route is part of the outcome"). P-3.
//
// It passes the pipeline's events through unchanged, with one rule on top: once cloud has been turned off for a
// cloud capture (or its key removed, or another provider selected), the next event is `finished(.cancelled(route:))`
// and nothing follows. The check runs after every event the pipeline gives, so no event decided after the turn-off
// reaches the consumer. Like `DraftEventSequence`, it never throws and `finished` comes exactly once, last.

import Foundation

public struct RoutedDraftEvents: AsyncSequence, Sendable {
    public typealias Element = DraftStreamEvent
    public typealias Failure = Never

    /// The router's handle on a cloud capture.
    struct CaptureWatch: Sendable {
        let router: ModelRouter
        let captureID: UInt64
    }

    let events: DraftEventSequence
    /// The route chosen for this capture, also carried by its outcome.
    public let route: Route
    let watch: CaptureWatch?

    init(events: DraftEventSequence, route: Route, watch: CaptureWatch?) {
        self.events = events
        self.route = route
        self.watch = watch
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(inner: events.makeAsyncIterator(), route: route, watch: watch)
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = DraftStreamEvent
        public typealias Failure = Never

        var inner: DraftEventSequence.Iterator
        let route: Route
        let watch: CaptureWatch?
        var isDone = false

        public mutating func next() async -> DraftStreamEvent? {
            await next(isolation: nil)
        }

        public mutating func next(isolation actor: isolated (any Actor)?) async -> DraftStreamEvent? {
            guard !isDone else { return nil }
            let event = await inner.next(isolation: actor)
            if let watch, await watch.router.captureEnded(watch.captureID) {
                isDone = true
                await watch.router.release(watch.captureID)
                return .finished(.cancelled(route: route))
            }
            guard let event else {
                isDone = true
                return nil
            }
            if case .finished = event {
                isDone = true
                if let watch { await watch.router.release(watch.captureID) }
            }
            return event
        }
    }
}
