// What a pasted provider key may hold (PO ruling R28-F5, 2026-11-27; brief AC-M2-21, AC-M2-23; review R28-F5). P-3,
// UX-3.
//
// - **Trimmed silently:** at both ends, every Unicode whitespace (spaces, tabs, line breaks incl. U+2028/U+2029,
//   no-break spaces), every control character (Cc) and the invisible U+200B, U+200C, U+200D, U+2060 and U+FEFF. The
//   key is stored trimmed, and its mask is computed from the trimmed key.
// - **Then refused unless** the key is non-empty and every character is in U+0021…U+007E (printable ASCII, no space).
//   A refused key is not saved, any earlier key for that provider is kept, and the one neutral result is
//   `CloudStoreError.keyTextNotAccepted`: it holds no character of the key and no position.
// - No length or prefix check: a short key is accepted (key validation is the optional ADR-0005 test prompt).
// Pure: no I/O, no logging.

import Foundation

public enum APIKeyText {
    /// The key text to store, trimmed; nil when the trimmed text is empty or holds a character outside
    /// U+0021…U+007E.
    public static func cleaned(_ raw: String) -> String? {
        let scalars = Array(raw.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !isEdgeTrimmed($0) }),
              let last = scalars.lastIndex(where: { !isEdgeTrimmed($0) }) else { return nil }
        let kept = scalars[first...last]
        guard kept.allSatisfy(isAccepted) else { return nil }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: kept)
        return String(text)
    }

    /// The key, trimmed, or nil when it must be refused.
    public static func cleaned(_ key: APIKey) -> APIKey? {
        key.withSecret { cleaned($0) }.map(APIKey.init)
    }

    /// Whether a key may go into an auth header as it is: non-empty and only U+0021…U+007E (the transport's check
    /// before sending, AC-M2-23).
    public static func isSendable(_ key: APIKey) -> Bool {
        key.withSecret { text in !text.isEmpty && text.unicodeScalars.allSatisfy(isAccepted) }
    }

    static func isAccepted(_ scalar: Unicode.Scalar) -> Bool {
        (0x21...0x7E).contains(scalar.value)
    }

    static let invisible: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]

    static func isEdgeTrimmed(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
            || invisible.contains(scalar.value)
    }
}
