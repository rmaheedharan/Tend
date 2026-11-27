// The masked display form of a provider key (WI-M2-M5; brief AC-M2-21 "Masked form", T-16). P-3, UX-3.
//
// The only form of a key that is ever returned for display: `••••` followed by the last 4 characters when the key has
// at least 12 characters, and `••••` alone for a shorter key. Save does not reject short keys (key validation is the
// optional ADR-0005 test prompt). Characters are Swift `Character`s (what the person sees).

import Foundation
import TendIngestion

public enum APIKeyMask {
    /// The four dots shown in place of the hidden part.
    public static let dots = "\u{2022}\u{2022}\u{2022}\u{2022}"

    /// The mask of the key as it is stored: trimmed by `APIKeyText` first (PO R28-F5). A key the store would refuse
    /// shows the dots only.
    public static func masked(_ key: APIKey) -> String {
        guard let cleaned = APIKeyText.cleaned(key) else { return dots }
        return cleaned.withSecret { text in
            text.count >= 12 ? dots + String(text.suffix(4)) : dots
        }
    }
}
