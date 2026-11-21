// Keywords of a text, exactly as the M2 brief's Definitions: used by the duplicate shortlist, the local word-match
// and the eval scorer (FR-A1; AC-M2-07, AC-M2-08, AC-M2-14). The stop-word list is closed; changing it after the
// AC-M2-14 freeze needs a PO decision.

import Foundation

public enum Keywords {

    /// The closed stop-word list (brief Definitions, "Keywords of a text").
    public static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "with", "from", "by", "about",
        "before", "after", "this", "that", "these", "those", "it", "its", "is", "are", "be", "been", "was", "were",
        "we", "us", "our", "i", "me", "my", "you", "your", "re", "s", "t", "ll", "ve", "d", "m", "need", "needs",
        "let", "lets", "get", "got", "some", "any", "all", "more", "almost", "out", "up", "again", "also", "just",
        "really", "please", "maybe", "should", "must", "can", "will", "would", "could", "do", "does", "did", "have",
        "has", "had", "if", "then", "so", "too", "very", "no", "not", "wait", "um", "uh", "like", "okay", "ok",
    ]

    /// The keywords of `text`: fold as name folding without stripping the article; split at every character that is
    /// not a Unicode letter or decimal digit; drop empty tokens and stop words; keep the distinct tokens, in order of
    /// first occurrence. No stemming.
    public static func of(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for token in tokens(of: TextFolding.foldWithoutArticle(text)) where !stopWords.contains(token) {
            if seen.insert(token).inserted { result.append(token) }
        }
        return result
    }

    /// Maximal runs of letters and decimal digits (already folded text in, tokens out).
    static func tokens(of folded: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in folded {
            if TextFolding.isLetter(character) || TextFolding.isDecimalDigit(character) {
                current.append(character)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
