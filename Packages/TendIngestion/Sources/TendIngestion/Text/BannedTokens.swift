// The banned-token matcher for generated text (brief Definitions, "Banned tokens"): split at non-letters, then
// name-fold, then compare whole tokens. UX-3 (Zero-Guilt). The calm-words guard (AC-M2-12, WI-M2-04) builds on this.
//
// The list itself must live in the shipped module, because the guard needs it. The AC-M1-02 vocabulary scan of the
// module Sources (AC-M2-12, `CalmVocabularyScanTests`) exempts exactly the string literals of the one `all`
// declaration below, once each (`BannedTokenListExemption`, dev-notes WI-M2-04 E1). Keep the declaration's first line
// as it is: the exemption is anchored on it, and fails closed (flags all nine) if it changes.

import Foundation

/// One banned token found in a text: the folded token and where it is in the original text.
public struct BannedTokenMatch: Sendable, Equatable {
    /// The folded banned token, one of `BannedTokens.all`.
    public let token: String
    /// The range of the original (unfolded) letters.
    public let range: Range<String.Index>
}

public enum BannedTokens {

    /// The AC-M1-02 list (brief Definitions). Changing it needs a PO decision.
    public static let all: [String] = [
        "overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt", "streak",
    ]

    static let set = Set(all)

    /// Every banned whole token in `text`, in order. A token is a maximal run of Unicode letters (digits and every other
    /// character split); it matches when its name fold equals a banned token.
    public static func matches(in text: String) -> [BannedTokenMatch] {
        letterRuns(in: text).compactMap { range in
            let folded = TextFolding.foldName(String(text[range]))
            return set.contains(folded) ? BannedTokenMatch(token: folded, range: range) : nil
        }
    }

    /// `true` when `text` contains a banned whole token.
    public static func containsBannedToken(_ text: String) -> Bool {
        !matches(in: text).isEmpty
    }

    /// The folded banned tokens of `text`, as a set (used to ask whether the user said a token).
    public static func tokens(in text: String) -> Set<String> {
        Set(matches(in: text).map(\.token))
    }

    /// Ranges of maximal runs of letters (`TextFolding.isLetter`), at character granularity.
    static func letterRuns(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if TextFolding.isLetter(text[index]) {
                if start == nil { start = index }
            } else if let runStart = start {
                result.append(runStart..<index)
                start = nil
            }
            index = next
        }
        if let runStart = start { result.append(runStart..<text.endIndex) }
        return result
    }
}
