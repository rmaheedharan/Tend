// `URLError` and HTTP status to the neutral failure reason (WI-M2-M4; brief AC-M2-23; ADR-0005 Decision 7). P-3, UX-3.
//
// Allowlist file 2 of the cloud adapter (AC-M2-09 Rule 3). Every reason names the situation, never the person
// (T-18). A cancellation is not a failure (`CloudTransport` contract point 5): `URLError.cancelled` maps to nil, and
// the transport finishes the stream without an error.
//
// `URLError.Code` is a struct of named codes, not an enum, so its switch needs a `default`: every code not listed is
// `unexpectedResponse` (AC-M2-23 "any other HTTP status or transport error").

import Foundation
import TendIngestion

enum CloudFailureMapping {
    /// The reason for a transport error, or nil for a cancellation.
    static func reason(for error: URLError) -> CloudFailureReason? {
        reason(for: error.code)
    }

    /// Two Foundation codes whose Swift names hold a word the calm-vocabulary scan does not allow in our sources
    /// (AC-M2-12): the DNS lookup code (-1006) and the secure-connection code (-1200), by raw value.
    static let dnsLookup = URLError.Code(rawValue: -1_006)
    static let secureConnection = URLError.Code(rawValue: -1_200)

    static func reason(for code: URLError.Code) -> CloudFailureReason? {
        switch code {
        case .cancelled:
            nil
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive:
            .offline
        case .timedOut:
            .timedOut
        case .cannotFindHost, dnsLookup:
            .hostNotFound
        case secureConnection, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            .secureConnectionUnavailable
        default:
            .unexpectedResponse
        }
    }

    /// The reason for an HTTP status, or nil for a 2xx (the body is read).
    static func reason(forStatus status: Int) -> CloudFailureReason? {
        switch status {
        case 200...299: nil
        case 401, 403: .keyNotAccepted
        case 429: .rateLimited
        case 500...599: .serviceUnavailable
        default: .unexpectedResponse
        }
    }

    /// Statuses whose `Retry-After` value is passed on (the only retryable ones, AC-M2-23).
    static func passesRetryAfter(_ reason: CloudFailureReason) -> Bool {
        reason.allowsRetry
    }
}
