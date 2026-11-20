import Foundation

/// The tone of any prompt the engine asks a later surface to show (AC-M1-18, design.md).
/// It has exactly one case on purpose: tone never rises, never varies between passes, and is never stored per task.
/// The wording lives in the M3 String Catalog; `TendCore` emits codes only.
public enum PromptTone: String, CaseIterable, Codable, Hashable, Sendable {
    case gentle
}
