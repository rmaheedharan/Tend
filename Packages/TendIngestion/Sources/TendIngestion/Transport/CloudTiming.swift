// The cloud deadline, the per-attempt timeouts and the single retry rule (brief AC-M2-22 "Timeouts", Q22, T-17, T-28;
// AC-M2-23). FR-A1, P-3, P-4.
//
// - Each capture has a deadline of 10.0 s from the moment the pipeline receives the input, on an injected clock.
// - Each attempt: resource timeout = time left; request (idle) timeout = min(time left, 4.0 s).
// - One retry, only for 429/5xx (`CloudFailureReason.allowsRetry`), after a pause p = max(0.5 s, `Retry-After`).
//   `Retry-After` is read only in its delta-seconds form; a missing or unreadable value counts as 0.
// - The retry starts only if ≥ 3.0 s are left before the deadline after the pause.
// The numbers are PO defaults (Q22; the owner may tighten them). Arithmetic is in `Duration` (exact for these values);
// only the timeouts handed to the transport are `Double` seconds. Pure values: no clock, no I/O.

import Foundation

public enum CloudTiming {
    /// The cloud deadline of one capture (Q15, Q22).
    public static let captureDeadline: Duration = .seconds(10)
    /// The cap on the request (idle) timeout.
    public static let requestIdleLimit: Duration = .seconds(4)
    /// The shortest pause before the retry.
    public static let minimumRetryPause: Duration = .milliseconds(500)
    /// The time that must be left before the deadline after the pause for the retry to start.
    public static let minimumTimeLeftForRetry: Duration = .seconds(3)
    /// The first attempt and the one retry.
    public static let maximumAttempts = 2

    /// The timeouts of an attempt that starts with `timeLeft` before the deadline.
    public static func timeouts(timeLeft: Duration) -> CloudAttemptTimeouts {
        CloudAttemptTimeouts(resource: seconds(timeLeft), request: seconds(min(timeLeft, requestIdleLimit)))
    }

    /// A duration as `Double` seconds.
    public static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// The `Retry-After` field, delta-seconds form only (RFC 9110 `delay-seconds = 1*DIGIT`; T-28).
public enum RetryAfterField {
    /// Values above this are read as this; any of them is far beyond the deadline, so there is no retry.
    public static let largestValue = 999_999_999

    /// The delay in whole seconds: the field value with spaces and tabs trimmed at both ends must be one or more ASCII
    /// digits. Missing, empty, an HTTP-date, a fraction, a sign or anything else counts as 0.
    public static func delaySeconds(_ value: String?) -> Int {
        guard let value else { return 0 }
        let bytes = Array(value.utf8)
        let isSpace: (UInt8) -> Bool = { $0 == 0x20 || $0 == 0x09 }
        guard let first = bytes.firstIndex(where: { !isSpace($0) }),
              let last = bytes.lastIndex(where: { !isSpace($0) }) else { return 0 }
        let digits = bytes[first...last]
        guard digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return 0 }
        var result = 0
        for digit in digits {
            result = result * 10 + Int(digit - 0x30)
            if result > largestValue { return largestValue }
        }
        return result
    }
}

/// The single retry rule (AC-M2-22, AC-M2-23).
public enum CloudRetryRule {
    /// The pause before the one retry, or nil when there is no retry: the failure is not 429/5xx, this was not the
    /// first attempt, body bytes were already read, or fewer than 3.0 s would be left after the pause.
    public static func pause(after failure: CloudTransportFailure, attempt: Int, bodyStarted: Bool,
                             timeLeft: Duration) -> Duration? {
        guard failure.reason.allowsRetry, attempt < CloudTiming.maximumAttempts, !bodyStarted else { return nil }
        let pause = max(CloudTiming.minimumRetryPause, .seconds(RetryAfterField.delaySeconds(failure.retryAfter)))
        guard timeLeft - pause >= CloudTiming.minimumTimeLeftForRetry else { return nil }
        return pause
    }
}
