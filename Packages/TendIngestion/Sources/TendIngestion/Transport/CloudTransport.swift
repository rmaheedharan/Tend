// The neutral cloud transport (plan WI-M2-14, N-2; brief AC-M2-22, AC-M2-23; ADR-0005 Decisions 6 and 7). FR-A1, P-2,
// P-3, P-4, UX-3.
//
// The protocol speaks only plain values: the payload builder's `CloudRequest` in, the per-attempt timeouts as plain
// `Double` seconds, and a stream of body byte chunks or a `CloudTransportFailure` out. So the `TendEval` recording
// wrapper (AC-M2-28, Rule 6) needs no `URL*` type, and the deadline and retry rule is tested on Linux.
//
// The real conformance is `CloudHTTPTransport` in `TendAI` (WI-M2-M4, owner-run Mac): an ephemeral `URLSession`
// configuration with `timeoutIntervalForResource = timeouts.resource` and `timeoutIntervalForRequest =
// timeouts.request`, HTTPS to the routed provider's host only, redirects refused, and `CloudFailureMapping` from each
// `URLError` and HTTP status to a `CloudFailureReason`. The retry is not the transport's: `CloudResponseBody` decides it.
// Pure values: no I/O, no clock, no logging.

import Foundation

/// The timeouts for one attempt, in seconds (brief AC-M2-22, Q22).
public struct CloudAttemptTimeouts: Hashable, Sendable {
    /// For `timeoutIntervalForResource`: the time left before the capture's deadline.
    public let resource: Double
    /// For `timeoutIntervalForRequest` (the idle timeout): min(time left, 4.0 s).
    public let request: Double

    public init(resource: Double, request: Double) {
        self.resource = resource
        self.request = request
    }
}

/// Why one attempt ended without a usable body (brief AC-M2-23). Neutral: each case names the situation, never the
/// person or the provider (T-18), and holds no banned token (AC-M2-12).
public enum CloudFailureReason: CaseIterable, Hashable, Sendable {
    /// No network connection.
    case offline
    /// A request or resource timeout passed.
    case timedOut
    /// The provider's host name could not be resolved (DNS).
    case hostNotFound
    /// A secure (TLS) connection could not be set up.
    case secureConnectionUnavailable
    /// HTTP 401 or 403: the provider did not accept the stored key.
    case keyNotAccepted
    /// HTTP 429.
    case rateLimited
    /// HTTP 5xx.
    case serviceUnavailable
    /// The transport refused the request before sending it: a host other than the routed provider's, a redirect to
    /// another host, or a non-HTTPS URL (AC-M2-22).
    case requestNotSent
    /// Any other HTTP status or transport error.
    case unexpectedResponse

    /// The neutral reason the draft stream reports (`noModel` before a draft, `interrupted` after one).
    public var stopReason: ModelStopReason {
        switch self {
        case .offline: .offline
        case .timedOut: .timedOut
        case .hostNotFound: .hostNotFound
        case .secureConnectionUnavailable: .secureConnectionUnavailable
        case .keyNotAccepted: .keyNotAccepted
        case .rateLimited: .rateLimited
        case .serviceUnavailable: .serviceUnavailable
        case .requestNotSent, .unexpectedResponse: .otherModelError
        }
    }

    /// Only 429 and 5xx may be retried, once, inside the deadline (AC-M2-23).
    public var allowsRetry: Bool {
        switch self {
        case .rateLimited, .serviceUnavailable: true
        default: false
        }
    }
}

/// The error a `CloudTransport` stream throws when an attempt ends without a usable body.
public struct CloudTransportFailure: Error, Hashable, Sendable {
    public let reason: CloudFailureReason
    /// The response's `Retry-After` field value exactly as received (429 and 5xx), or nil when there is none. It is read
    /// by `RetryAfterField` (delta-seconds only).
    public let retryAfter: String?

    public init(_ reason: CloudFailureReason, retryAfter: String? = nil) {
        self.reason = reason
        self.retryAfter = retryAfter
    }

    public var stopReason: ModelStopReason { reason.stopReason }
}

/// Sends one cloud request and streams its response body (plan N-2).
///
/// **Contract** (WI-M2-M4 conforms, on the owner-run Mac):
/// 1. Each call is one attempt: one HTTPS request for `request`, with `timeouts` applied to that attempt only.
/// 2. With a 2xx status, yield the body bytes in order, in chunks cut anywhere, then finish normally.
/// 3. Otherwise (except a cancelled attempt, point 5) finish by throwing a `CloudTransportFailure`: the status or
///    transport error mapped to its reason, and for 429 and 5xx the `Retry-After` field value as received. Never retry,
///    queue or store anything: the one allowed retry is decided by `CloudResponseBody`.
/// 4. Cancel the network task in the stream's `onTermination`, so a released stream sends and reads nothing more.
/// 5. A cancelled attempt (the reading task cancelled, or `onTermination` ran) is not a failure: finish the stream
///    without an error, or throw `CancellationError`. Never map `URLError.cancelled` (or any other cancellation) to a
///    `CloudFailureReason`; `CloudResponseBody` reports the cancellation itself (review R30-F2).
public protocol CloudTransport: Sendable {
    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error>
}
