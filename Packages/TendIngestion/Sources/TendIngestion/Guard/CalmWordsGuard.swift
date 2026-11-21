// The calm-words guard (AC-M2-12; brief S-M2-05, T-10; Q5 step 7). UX-3 (Zero-Guilt), FR-A1.
//
// Tend never adds a guilt word the user did not say. A banned token (AC-M1-02 list, `BannedTokens`) in a model title or
// a proposed room name is removed unless it occurs, as a whole token after name folding, anywhere in the whole input
// (the typed text or the final transcript). Banned tokens the user said are kept, because they are the user's words.

import Foundation

/// Why the guard drops an item (a typed reason; the name holds no banned token, AC-M2-12).
public enum CalmWordsSkipReason: String, Sendable, Equatable, CaseIterable {
    /// The title had no words left after the guard, and there was no usable `sourcePhrase` to stand in for it.
    case noTitleWordsLeft
}

/// The guard's result for one item.
public enum CalmWordsDecision: Sendable, Equatable {
    /// Keep the item with this title (non-empty) and room.
    case keep(title: String, room: DraftRoom)
    /// Drop the item.
    case skip(CalmWordsSkipReason)
}

public enum CalmWordsGuard {

    /// Removes every banned whole token of `text` that is not a token of `input` (both compared after name folding).
    /// After a removal, whitespace runs collapse to one space and whitespace and punctuation (Unicode general category
    /// P*) are trimmed at both ends. With no removal, `text` is returned unchanged.
    public static func calmed(_ text: String, input: String) -> String {
        let said = BannedTokens.tokens(in: input)
        let removals = BannedTokens.matches(in: text).filter { !said.contains($0.token) }
        guard !removals.isEmpty else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in removals {
            result += text[cursor..<match.range.lowerBound]
            cursor = match.range.upperBound
        }
        result += text[cursor...]
        return trimEnds(TextFolding.collapseWhitespace(result))
    }

    /// The guard step for one item (AC-M2-12):
    /// - the title is calmed; if nothing is left, it becomes the `sourcePhrase`, but only one that passes the
    ///   `sourcePhrase` check (`SourcePhrase.checked`), trimmed and collapsed, and itself calmed (so a fallback title
    ///   never carries an introduced token either); if that is nil or empty, the item is skipped;
    /// - a proposed room name is calmed; if nothing is left, the room is `none`. Existing rooms and `none` are kept:
    ///   they hold no model words.
    public static func apply(title: String, room: DraftRoom, sourcePhrase: String?, input: String) -> CalmWordsDecision {
        var keptTitle = calmed(title, input: input)
        if isBlank(keptTitle) {
            let fallback = SourcePhrase.checked(sourcePhrase, input: input)
                .map { calmed(TextFolding.collapseWhitespace($0), input: input) } ?? ""
            guard !isBlank(fallback) else { return .skip(.noTitleWordsLeft) }
            keptTitle = fallback
        }
        var keptRoom = room
        if case let .proposed(name) = room {
            let calmedName = calmed(name, input: input)
            keptRoom = isBlank(calmedName) ? .none : .proposed(calmedName)
        }
        return .keep(title: keptTitle, room: keptRoom)
    }

    static func isBlank(_ text: String) -> Bool {
        TextFolding.collapseWhitespace(text).isEmpty
    }

    /// Trims whitespace and punctuation at both ends (text already collapsed).
    static func trimEnds(_ text: String) -> String {
        var characters = Substring(text)
        while let first = characters.first, isTrimmable(first) { characters.removeFirst() }
        while let last = characters.last, isTrimmable(last) { characters.removeLast() }
        return String(characters)
    }

    /// Whitespace or punctuation (first scalar of the character in Unicode `White_Space` or a P* category).
    static func isTrimmable(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        if first.properties.isWhitespace { return true }
        switch first.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }
}
