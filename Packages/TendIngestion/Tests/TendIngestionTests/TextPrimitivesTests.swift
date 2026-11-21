// Text primitives: name folding (T-09), keywords of a text and the closed stop-word list, the banned-token matcher
// (brief Definitions). FR-A1, UX-3. Plan WI-M2-01. Expected values are written from the brief, not from the code.
//
// Platform pins (risk R-10): the `ß` → `ss` and fullwidth cases record what Linux Foundation gives. The Darwin rerun
// (plan B2) must give the same bytes; a difference is a defect, not a skip.

import Testing
@testable import TendIngestion

@Suite("Text primitives: name folding, keywords, stop words, banned tokens (FR-A1, UX-3)")
struct TextPrimitivesTests {

    // MARK: Name folding

    @Test("Name folding: trim, collapse, ASCII quotes, case/diacritic/width fold, one leading article", arguments: [
        ("  The   Kitchen ", "kitchen"),
        ("Living\tRoom\n", "living room"),
        ("\u{3000}Hall\u{00A0}way\u{2003}", "hall way"),     // ideographic space, no-break space, em space
        ("A  Bathroom", "bathroom"),
        ("An Attic", "attic"),
        ("My room", "room"),
        ("OUR  Garage", "garage"),
        ("the the hall", "the hall"),                        // one article only
        ("Thé Kitchen", "kitchen"),                          // folded first, then stripped
        ("the", "the"),                                      // nothing after the article: kept
        ("A", "a"),
        ("Theatre Room", "theatre room"),                    // not a whole-word article
        ("Another room", "another room"),
        ("the-kitchen", "the-kitchen"),                      // no space after the article
        ("Kid\u{2019}s Room", "kid's room"),                 // ’ → '
        ("\u{2018}Den\u{2019}", "'den'"),
        ("\u{201C}Den\u{201D}", "\"den\""),                  // “ ” → "
        ("\u{201E}Den\u{201F}", "\"den\""),
        ("Kid\u{02BC}s", "kid's"),
        ("Café", "cafe"),
        ("Cafe\u{0301}", "cafe"),                            // decomposed accent
        ("ＧＡＲＡＧＥ", "garage"),                           // fullwidth (width fold)
        ("Straße", "strasse"),                               // R-10 pin: full case fold on Linux
        ("", ""),
        ("   ", ""),
        ("Utility room 2", "utility room 2"),
        // R1-F7: a lone combining mark between spaces. The fold removes it, then the collapse runs, so one space is
        // left. (In the brief's listed order, collapse before fold, two spaces would remain; PO/Tester informed.)
        ("x \u{301} y", "x y"),
        ("a \u{301} b", "b"),                           // then "a" is a leading article and is stripped
    ])
    func nameFolding(input: String, expected: String) {
        #expect(TextFolding.foldName(input) == expected, "fold(\(input.debugDescription))")
    }

    @Test("Name folding is idempotent and matching is exact equality (no plural or stem folding)")
    func nameFoldingEquality() {
        for name in ["The Kitchen", "Kid’s room", "ＧＡＲＡＧＥ", "Café"] {
            let once = TextFolding.foldName(name)
            // Idempotent except for a second article ("the the x" folds once per call by design).
            #expect(TextFolding.foldName(once) == once)
        }
        #expect(TextFolding.foldName("the kitchen") == TextFolding.foldName("KITCHEN"))
        #expect(TextFolding.foldName("kitchens") != TextFolding.foldName("kitchen"))
        #expect(TextFolding.foldName("bath room") != TextFolding.foldName("bathroom"))
    }

    // MARK: Keywords

    @Test("Keywords of a text: fold (article kept), split at non-letter/digit, drop stop words, distinct in order",
          arguments: [
            ("We're almost out of dishwasher pods", ["dishwasher", "pods"]),
            ("The AC needs servicing before summer", ["ac", "servicing", "summer"]),
            ("Deep-clean the balcony, the BALCONY!", ["deep", "clean", "balcony"]),
            ("let's deep clean the balcony this weekend if it doesn't rain",
             ["deep", "clean", "balcony", "weekend", "doesn", "rain"]),
            ("Buy 2 bins x2", ["buy", "2", "bins", "x2"]),
            ("Kid’s room", ["kid", "room"]),
            ("um, like, okay, no wait", []),
            ("No wait, Thursday", ["thursday"]),
            ("café Café CAFE", ["cafe"]),
            ("½ cup", ["cup"]),                       // U+00BD is No, not Nd: a separator
            ("e-mail_list", ["e", "mail", "list"]),    // `_` and `-` split
            ("The kitchen", ["kitchen"]),             // "the" is a stop word, not stripped as an article
            ("", []),
            ("   ", []),
          ])
    func keywords(input: String, expected: [String]) {
        #expect(Keywords.of(input) == expected, "keywords(\(input.debugDescription))")
    }

    @Test("The stop-word list is exactly the brief's closed list (89 words)")
    func stopWordListIsClosed() {
        // Re-typed from the brief (Definitions, "Keywords of a text"), as an independent copy.
        let brief = """
            a, an, the, and, or, but, of, to, in, on, at, for, with, from, by, about, before, after, this, that, these, \
            those, it, its, is, are, be, been, was, were, we, us, our, i, me, my, you, your, re, s, t, ll, ve, d, m, \
            need, needs, let, lets, get, got, some, any, all, more, almost, out, up, again, also, just, really, please, \
            maybe, should, must, can, will, would, could, do, does, did, have, has, had, if, then, so, too, very, no, \
            not, wait, um, uh, like, okay, ok
            """
        let words = brief.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(words.count == 89)
        #expect(Set(words).count == words.count)
        #expect(Keywords.stopWords == Set(words))
    }

    // MARK: Banned tokens

    @Test("Banned-token list is the AC-M1-02 list")
    func bannedList() {
        #expect(BannedTokens.all == ["overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt",
                                     "streak"])
    }

    @Test("Banned tokens are matched as whole tokens after splitting at non-letters and name folding", arguments: [
        ("Pay the late fee", ["late"]),
        ("LATE", ["late"]),
        ("Lâte notice", ["late"]),
        ("La\u{0302}te notice", ["late"]),         // decomposed: the accent stays with its letter
        ("ｌａｔｅ", ["late"]),                      // fullwidth letters
        ("late2", ["late"]),                       // digits split
        ("2late", ["late"]),
        ("behind_schedule", ["behind"]),           // `_` splits
        ("overdue's", ["overdue"]),
        ("Debt.", ["debt"]),
        ("overdue late lateness missed failed behind penalty debt streak",
         ["overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt", "streak"]),
        ("latest template translate plated", []),
        ("over-due", []),                          // two tokens, neither banned
        ("streaks debts", []),                     // no plural folding
        ("unfailed", []),
        ("", []),
    ])
    func bannedTokenMatching(input: String, expected: [String]) {
        #expect(BannedTokens.matches(in: input).map(\.token) == expected, "matches(\(input.debugDescription))")
        #expect(BannedTokens.containsBannedToken(input) == !expected.isEmpty)
    }

    @Test("Banned-token matches carry the range of the original letters")
    func bannedTokenRanges() {
        let text = "Pay the LÂTE fee, not late2"
        let found = BannedTokens.matches(in: text)
        #expect(found.map { String(text[$0.range]) } == ["LÂTE", "late"])
        #expect(BannedTokens.tokens(in: text) == ["late"])
    }

    // MARK: UTF-8 order

    @Test("UTF-8 byte order differs from UTF-16 order where it should")
    func utf8Order() {
        // U+FF5E (EF BD 9E) precedes U+1F600 (F0 9F 98 80) in UTF-8; in UTF-16 the surrogate D83D comes first.
        #expect(TextFolding.utf8Precedes("\u{FF5E}", "\u{1F600}"))
        #expect(!TextFolding.utf8Precedes("\u{1F600}", "\u{FF5E}"))
        #expect(TextFolding.utf8Precedes("B", "a"))
        #expect(TextFolding.utf8Precedes("e\u{0301}", "é"))  // 65 CC 81 < C3 A9, though the Strings are ==
        #expect(!TextFolding.utf8Precedes("a", "a"))
    }
}
