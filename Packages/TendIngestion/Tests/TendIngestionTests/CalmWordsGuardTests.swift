// AC-M2-12: the calm-words guard (brief S-M2-05, T-10). UX-3 (Zero-Guilt), FR-A1. Plan WI-M2-04.
//
// Expected values are written from the brief's rules, not from the code:
// - tokens are split at non-letters and compared after name folding, as whole tokens;
// - a banned token that does not occur anywhere in the whole input is removed from the title and from a proposed
//   room name; a banned token the user said is kept;
// - after a removal, whitespace runs collapse to one space, and whitespace and punctuation are trimmed at both ends;
// - an empty title becomes the draft's `sourcePhrase`; if that is nil or empty, the item is skipped with a typed
//   reason; an empty proposed room name becomes `none`.
// The input sentence is the brief's Outcome example, so the "not in the input" cases use the brief's own words.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("AC-M2-12 calm-words guard (UX-3)")
struct CalmWordsGuardTests {

    /// The brief's Outcome example sentence (brief, "Outcome"). It contains no banned token.
    static let briefInput = "The AC needs servicing before summer, we're almost out of dishwasher pods, and let's deep "
        + "clean the balcony this weekend if it doesn't rain"

    // MARK: Removal of introduced tokens, tidy-up, whole tokens

    @Test("AC-M2-12: a banned token that is not in the input is removed, and the text is tidied", arguments: [
        // (model text, expected after the guard)
        ("Service the AC late", "Service the AC"),
        ("Overdue: service the AC", "service the AC"),                       // punctuation trimmed at the start
        ("Buy dishwasher pods (late)", "Buy dishwasher pods"),               // "()" trimmed at the end
        ("Deep clean the balcony, missed", "Deep clean the balcony"),
        ("Pay the  late  fee", "Pay the fee"),                               // the run left behind collapses
        ("Deep clean balcony, late fee", "Deep clean balcony, fee"),         // inner punctuation is kept
        ("Missed penalty: debt behind summer", "summer"),                    // several tokens, then trim
        ("Service the AC!!! failed", "Service the AC"),                      // trailing run of punctuation
        ("— late — service the AC —", "service the AC"),                     // dashes are punctuation
        ("late-night pods run", "night pods run"),                           // split at the hyphen (non-letter)
        ("streak2 balcony", "2 balcony"),                                    // split at the digit; the digit stays
        ("Service the AC $late", "Service the AC $"),                        // `$` is a symbol, not punctuation
    ])
    func removesIntroducedTokens(modelText: String, expected: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: Self.briefInput) == expected)
    }

    @Test("AC-M2-12: every banned token of the AC-M1-02 list is removed when the input does not contain it",
          arguments: ["overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt", "streak"])
    func everyListedTokenIsRemoved(token: String) {
        #expect(CalmWordsGuard.calmed("Service the AC \(token)", input: Self.briefInput) == "Service the AC")
        #expect(CalmWordsGuard.calmed("\(token.uppercased()) pods", input: Self.briefInput) == "pods")
    }

    @Test("AC-M2-12: matching is after name folding (case, diacritics, width, typographic quotes)", arguments: [
        ("Service the AC LATE", "Service the AC"),
        ("Service the AC Laté", "Service the AC"),                           // diacritic fold
        ("Service the AC ＬＡＴＥ", "Service the AC"),                         // width fold
        ("Service the AC Late\u{0301}", "Service the AC"),                   // decomposed accent stays in the token
        ("\u{201C}Overdue\u{201D} pods", "pods"),                            // “ ” are punctuation and are trimmed
    ])
    func matchingIsFolded(modelText: String, expected: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: Self.briefInput) == expected)
    }

    @Test("AC-M2-12: only whole tokens match; words that merely contain a banned token are kept", arguments: [
        "Water the latex plant",            // latex
        "Plate the summer salad",           // plate
        "Behindhand balcony clean",         // one token "behindhand"
        "Failedness check",                 // one token
        "Debtor letter",                    // one token
        "Streaky windows",                  // one token
        "Translate the AC manual",          // translate
    ])
    func wholeTokensOnly(modelText: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: Self.briefInput) == modelText)
    }

    @Test("AC-M2-12: with no removal the text is returned unchanged (no tidy-up)", arguments: [
        "Service the AC!",
        "(Balcony) deep clean",
        "Pods, dishwasher",
    ])
    func unchangedWithoutRemoval(modelText: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: Self.briefInput) == modelText)
    }

    // MARK: The user's own words are kept

    @Test("AC-M2-12: banned tokens the user said are kept, because they are the user's words", arguments: [
        // (input, model text, expected)
        ("I'm late paying the electricity bill", "Pay the late electricity bill", "Pay the late electricity bill"),
        ("the LATE fee for the library", "Pay late fee", "Pay late fee"),             // folded comparison
        ("pay the laté fee", "Pay LATE fee", "Pay LATE fee"),                          // diacritics fold both sides
        ("we missed the bin day, and the rent is overdue", "Overdue rent, missed bins", "Overdue rent, missed bins"),
        // Mixed: "late" was said, "overdue" was not.
        ("the late fee", "Pay overdue late fee", "Pay late fee"),
        // Anywhere in the whole input, not only near the item.
        ("Buy pods. Also, the library book is late, and clean the balcony", "Return late library book",
         "Return late library book"),
        // The whole input is a multi-line transcript.
        ("first the dishes\nthen the streak on the window", "Wipe the window streak", "Wipe the window streak"),
    ])
    func userWordsKept(input: String, modelText: String, expected: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: input) == expected)
    }

    @Test("AC-M2-12: the input is also compared as whole tokens (a longer word in the input does not allow its prefix)",
          arguments: [
        // (input, model text, expected)
        ("sorry for my lateness", "Fix lateness and late fee", "Fix lateness and fee"),
        ("the latex gloves", "Buy late latex gloves", "Buy latex gloves"),
        ("behindhand with the pods", "Behind on pods", "on pods"),
    ])
    func inputComparedAsWholeTokens(input: String, modelText: String, expected: String) {
        #expect(CalmWordsGuard.calmed(modelText, input: input) == expected)
    }

    // MARK: Title, sourcePhrase and room together (the guard step, Q5 step 7)

    @Test("AC-M2-12: a title the guard empties becomes the draft's sourcePhrase")
    func emptyTitleBecomesSourcePhrase() {
        let decision = CalmWordsGuard.apply(title: "Overdue!", room: .none,
                                            sourcePhrase: "deep clean the balcony", input: Self.briefInput)
        #expect(decision == .keep(title: "deep clean the balcony", room: .none))
    }

    @Test("AC-M2-12: an empty title with a nil, empty or unverifiable sourcePhrase is skipped with a typed reason",
          arguments: [
        nil,
        "",
        "   \n ",
        "mow the lawn",            // not in the input (strict: an unverified phrase is not the user's words)
    ] as [String?])
    func emptyTitleSkipped(sourcePhrase: String?) {
        let decision = CalmWordsGuard.apply(title: "late, missed", room: .proposed("Balcony"),
                                            sourcePhrase: sourcePhrase, input: Self.briefInput)
        #expect(decision == .skip(.noTitleWordsLeft))
    }

    @Test("AC-M2-12: the fallback sourcePhrase is trimmed and collapsed for use as the title")
    func fallbackTitleIsTidied() {
        let decision = CalmWordsGuard.apply(title: "LATE", room: .none,
                                            sourcePhrase: "  deep   clean the balcony ", input: Self.briefInput)
        #expect(decision == .keep(title: "deep clean the balcony", room: .none))
    }

    @Test("AC-M2-12: a fallback sourcePhrase never carries an introduced banned token (strict reading)")
    func fallbackTitleIsGuarded() {
        // "late" is a substring of the folded input ("lateness"), so the phrase passes the substring check, but it is
        // not a whole token of the input, so the guard removes it and the item is skipped.
        let decision = CalmWordsGuard.apply(title: "Overdue", room: .none,
                                            sourcePhrase: "late", input: "sorry for my lateness")
        #expect(decision == .skip(.noTitleWordsLeft))
    }

    @Test("AC-M2-12: the guard applies to a proposed room name; an emptied name becomes none", arguments: [
        // (proposed name, expected room)
        ("Late room", DraftRoom.proposed("room")),
        ("Overdue", DraftRoom.none),
        ("(missed)", DraftRoom.none),
        ("Balcony", DraftRoom.proposed("Balcony")),
        ("Balcony, behind", DraftRoom.proposed("Balcony")),
    ])
    func proposedRoomNameGuarded(name: String, expected: DraftRoom) {
        let decision = CalmWordsGuard.apply(title: "Deep clean", room: .proposed(name),
                                            sourcePhrase: nil, input: Self.briefInput)
        #expect(decision == .keep(title: "Deep clean", room: expected))
    }

    @Test("AC-M2-12: a proposed room name the user said is kept")
    func proposedRoomNameUserWordsKept() {
        let input = "tidy the penalty box room after the match"
        let decision = CalmWordsGuard.apply(title: "Tidy", room: .proposed("Penalty box room"),
                                            sourcePhrase: nil, input: input)
        #expect(decision == .keep(title: "Tidy", room: .proposed("Penalty box room")))
    }

    @Test("AC-M2-12: existing rooms and no room are not changed by the guard (they introduce no model words)")
    func existingAndNoRoomUnchanged() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID()
        #expect(CalmWordsGuard.apply(title: "Clean late", room: .existing(id), sourcePhrase: nil,
                                     input: Self.briefInput) == .keep(title: "Clean", room: .existing(id)))
        #expect(CalmWordsGuard.apply(title: "Clean", room: .none, sourcePhrase: nil,
                                     input: Self.briefInput) == .keep(title: "Clean", room: .none))
    }

    @Test("AC-M2-12: a title the guard does not empty keeps its words and ignores the sourcePhrase")
    func titleKeptWhenNotEmpty() {
        let decision = CalmWordsGuard.apply(title: "Service the AC, overdue", room: .none,
                                            sourcePhrase: "The AC needs servicing", input: Self.briefInput)
        #expect(decision == .keep(title: "Service the AC", room: .none))
    }

    // MARK: Invariant over generated outputs

    @Test("AC-M2-12: over 2,000 seeded outputs, no guarded title or room name holds a token absent from the input")
    func noIntroducedTokensProperty() {
        let seed: UInt64 = 0x0CA1_3E5E_ED00_0412
        var generator = SplitMix64(seed: seed)
        let words = ["clean", "the", "late", "Overdue", "pods", "BEHIND", "balcony", "laté", "missed,", "(debt)",
                     "streak2", "AC", "—", "!", "penalty:", "fee", "lateness", "failed.", "  ", "summer"]
        func phrase(_ count: Int) -> String {
            (0..<count).map { _ in words[Int(generator.next() % UInt64(words.count))] }.joined(separator: " ")
        }
        var removals = 0
        for index in 0..<2_000 {
            let input = phrase(Int(generator.next() % 8))
            let title = phrase(1 + Int(generator.next() % 6))
            let room = phrase(Int(generator.next() % 3))
            let allowed = BannedTokens.tokens(in: input)
            let decision = CalmWordsGuard.apply(title: title, room: .proposed(room), sourcePhrase: input, input: input)
            switch decision {
            case let .keep(keptTitle, keptRoom):
                #expect(BannedTokens.tokens(in: keptTitle).isSubset(of: allowed), "seed \(seed) case \(index)")
                #expect(!keptTitle.isEmpty, "seed \(seed) case \(index)")
                if case let .proposed(name) = keptRoom {
                    #expect(BannedTokens.tokens(in: name).isSubset(of: allowed), "seed \(seed) case \(index)")
                    #expect(!name.isEmpty, "seed \(seed) case \(index)")
                }
                if keptTitle != title { removals += 1 }
            case .skip:
                // Only when the title had no words left and the input gave no usable phrase.
                #expect(TextFolding.collapseWhitespace(CalmWordsGuard.calmed(title, input: input)).isEmpty,
                        "seed \(seed) case \(index)")
            }
        }
        print("AC-M2-12 property: seed \(seed), 2000 cases, \(removals) titles changed by the guard")
        #expect(removals > 100)  // the generator exercises removal, not only pass-through
    }

    // MARK: Reason names

    @Test("AC-M2-12: every skip-reason case name contains no banned token (AC-M1-02 split and whole-token match)")
    func reasonNamesAreCalm() {
        for reason in CalmWordsSkipReason.allCases {
            let name = String(describing: reason)
            #expect(!BannedTokens.containsBannedToken(name), "\(name)")
            let camelTokens = name.reduce(into: [""]) { parts, character in
                if character.isUppercase { parts.append("") }
                parts[parts.count - 1].append(character)
            }
            for token in camelTokens {
                #expect(!BannedTokens.all.contains(token.lowercased()), "\(name) has \(token)")
            }
        }
        #expect(CalmWordsSkipReason.allCases.count == 1)
    }
}
