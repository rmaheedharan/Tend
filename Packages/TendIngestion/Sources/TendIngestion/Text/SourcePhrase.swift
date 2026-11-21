// The `sourcePhrase` check (brief Definitions, "Draft"; Q5 step 8). FR-A1.
//
// A draft's `sourcePhrase` is the user's own words for the item. It is kept only if it occurs in the input as a
// substring after name folding (applied to both sides). Otherwise it is nil.

import Foundation

public enum SourcePhrase {

    /// `phrase` exactly as given when its name fold is non-empty and is a substring (by `Character`) of the name fold
    /// of `input`; otherwise nil. The match is a plain substring, not a whole-word match.
    public static func checked(_ phrase: String?, input: String) -> String? {
        guard let phrase else { return nil }
        let needle = Array(TextFolding.foldName(phrase))
        guard !needle.isEmpty else { return nil }
        let haystack = Array(TextFolding.foldName(input))
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return phrase
        }
        return nil
    }
}
