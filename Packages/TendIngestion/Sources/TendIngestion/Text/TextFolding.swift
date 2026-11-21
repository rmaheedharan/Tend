// Name folding and keyword folding, exactly as the M2 brief's Definitions (T-09). FR-A1 (room linking, duplicate
// shortlist, sourcePhrase check), UX-3 (the calm-words guard compares folded tokens).
//
// Platform note (risk R-10): folding uses Foundation's `folding(options:locale:)` with the fixed `en_US_POSIX` locale.
// Whitespace, letters and digits are classified with the Swift standard library's Unicode properties, which are the
// same on Linux and Darwin. The Linux vectors are pinned in `TextFoldingTests`; the Darwin rerun (plan B2) must give
// the same results, and any difference is a defect.

import Foundation

/// The text folds the ingestion layer uses. Pure functions; no ambient locale (AC-M2-09 Rule 1).
public enum TextFolding {

    /// The one fixed locale for folding (AC-M2-09 Rule 1 allows exactly this locale).
    static let posix = Locale(identifier: "en_US_POSIX")

    /// The folding options the brief names.
    static let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// The leading articles that name folding strips (one, at most).
    public static let leadingArticles: [String] = ["the", "a", "an", "my", "our"]

    /// Typographic apostrophes and quotes mapped to ASCII before folding (closed list).
    /// Apostrophe-like: U+2018 ‘, U+2019 ’, U+201A ‚, U+201B ‛, U+2032 ′, U+02BC ʼ → `'`.
    /// Quote-like: U+201C “, U+201D ”, U+201E „, U+201F ‟, U+2033 ″ → `"`.
    public static let typographicQuotes: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{2032}": "'", "\u{02BC}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", "\u{2033}": "\"",
    ]

    /// Name folding (rooms, `sourcePhrase`, room keywords): map typographic quotes to ASCII; fold case, diacritics and
    /// width in `en_US_POSIX`; trim and collapse every whitespace run to one space; strip one leading article ("the",
    /// "a", "an", "my", "our") when it is a whole word followed by more text. Matching after folding is exact equality.
    public static func foldName(_ text: String) -> String {
        stripLeadingArticle(foldWithoutArticle(text))
    }

    /// The keyword fold: name folding without stripping the article.
    public static func foldWithoutArticle(_ text: String) -> String {
        collapseWhitespace(mapTypographicQuotes(text).folding(options: foldOptions, locale: posix))
    }

    /// Replaces the closed list of typographic quotes with ASCII.
    public static func mapTypographicQuotes(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(typographicQuotes[scalar] ?? scalar)
        }
        return String(scalars)
    }

    /// Trims whitespace at both ends and collapses each inner run of whitespace (Unicode `White_Space`, newlines
    /// included) to one U+0020 space.
    public static func collapseWhitespace(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
            } else {
                if pendingSpace { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Strips one leading article when it is followed by a space and more text ("the kitchen" → "kitchen"; "the" and
    /// "theatre room" are unchanged). Expects already folded and collapsed text.
    static func stripLeadingArticle(_ folded: String) -> String {
        for article in leadingArticles {
            let prefix = article + " "
            if folded.hasPrefix(prefix), folded.count > prefix.count {
                return String(folded.dropFirst(prefix.count))
            }
        }
        return folded
    }

    // MARK: - Character classes

    /// A Unicode letter: the first scalar of the character is in a letter category (Lu, Ll, Lt, Lm, Lo).
    public static func isLetter(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        switch first.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    /// A Unicode decimal digit: the first scalar of the character is in category Nd.
    public static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }

    /// Ascending UTF-8 byte order (used for canonical JSON keys and the duplicate shortlist's tie-breaks).
    public static func utf8Precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
