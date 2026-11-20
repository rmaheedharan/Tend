import Foundation

/// Why a task looks the way it does after one gentle rescheduling pass (rules R0–R4; FR-B2, UX-3; design.md naming
/// list). A reason code for later surfaces, never stored on the task (design D-2), never a count and never a judgement.
/// Copy keys are reserved in the M3 String Catalog; `reschedule.moved` and `reschedule.restEnded` are silent by default.
public enum RescheduleOutcome: String, CaseIterable, Hashable, Sendable {
    /// Nothing to renegotiate: completed, resting, or the window has not ended (R0, or no rule applies).
    case unchanged
    /// A deferral whose rest is over is offerable again, and its window has not ended (R1 only).
    case restEnded
    /// A deep clean whose window ended steps down to a light-touch version on its next eligible window (R2).
    case lightened
    /// A critical task whose window ended comes back gently on its next eligible window (R3).
    case broughtBackGently
    /// Any other task whose window ended moves to its next eligible window (R4).
    case movedToNextWindow
}
