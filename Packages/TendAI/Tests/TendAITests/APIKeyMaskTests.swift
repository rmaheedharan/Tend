// The masked key form (WI-M2-M5; brief AC-M2-21 "Masked form", T-16).

import Testing
import TendAI
import TendIngestion

@Suite("Masked key form (WI-M2-M5; AC-M2-21)")
struct APIKeyMaskTests {
    @Test("Twelve or more characters show four dots and the last four; shorter keys show four dots only",
          arguments: [
              ("", "••••"), ("abc", "••••"), ("12345678901", "••••"), ("123456789012", "••••9012"),
              ("sk-test-0123456789abcdWXYZ", "••••WXYZ"), ("\n sk-test-0123456789abcdWXYZ \u{200B}", "••••WXYZ"),   // R28-F5: from the trimmed key
              ("ключ-ключ-ключ-🔑ab", "••••"),   // R28-F5: a key the store refuses shows the dots only
          ])
    func mask(key: String, expected: String) {
        #expect(APIKeyMask.masked(APIKey(key)) == expected)
    }

    @Test("The mask never holds more than the last four characters")
    func neverMore() {
        let key = "sk-live-ABCDEFGHIJKLMNOP"
        let masked = APIKeyMask.masked(APIKey(key))
        #expect(masked.count == 8)
        #expect(!masked.contains("ABCD"))
    }
}
