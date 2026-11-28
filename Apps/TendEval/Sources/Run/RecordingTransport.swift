// The harness's transport wrapper (plan "Named files", N-2; AC-M2-28 "wraps the transport protocol to record
// metadata"). It forwards every attempt to the real transport unchanged and records only the request's byte count, its
// JSON key paths (array indices as `[]`, sorted, unique) and the per-array element counts of the body and of the
// user-content object (D-059, AC-M2-26): never a value, a body, a header or the key. It uses no networking type: only
// the neutral `CloudTransport` protocol.

import Foundation
import TendIngestion

final class RecordingTransport: CloudTransport, @unchecked Sendable {
    // @unchecked Sendable: `records` is touched only under `lock`; `inner` is Sendable and never changed.
    private let inner: any CloudTransport
    private let lock = NSLock()
    private var records: [EvalResultsFileV1.CloudRequestRecord] = []

    init(_ inner: any CloudTransport) {
        self.inner = inner
    }

    /// Clears the record before a capture.
    func reset() {
        lock.withLock { records = [] }
    }

    /// The attempts of the current capture, in order.
    var recorded: [EvalResultsFileV1.CloudRequestRecord] {
        lock.withLock { records }
    }

    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        let paths = CloudRequestKeyPaths.leafPaths(ofBody: request.body) ?? []
        lock.withLock {
            records.append(.init(
                attempt: records.count + 1, bytes: request.body.count, keyPaths: paths,
                arrayCounts: CloudRequestKeyPaths.arrayCounts(ofBody: request.body),
                userContentArrayCounts: CloudRequestKeyPaths.userContentArrayCounts(ofBody: request.body,
                                                                                    provider: request.provider)))
        }
        return inner.send(request, timeouts: timeouts)
    }
}
