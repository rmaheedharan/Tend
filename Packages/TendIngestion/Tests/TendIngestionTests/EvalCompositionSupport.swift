// The Linux composition check of the real M2 eval fixtures (WI-M2-16, AC-M2-14; brief rubric Q3 "Composition", brief
// "Eval scoring rules" (Fixed IDs, Distinguishable targets), plan "Eval harness ID generator" (version-4 fixture UUIDs),
// N-3 (no 600…729 digit run), UX-3 (no banned token), PO `po-m2-wi16.md` rulings 1–9).
//
// The Acceptance Tester writes the fixtures (AC-M2-14 "Authorship"); this file only checks them. Rule IDs follow the
// Tester's table in `docs/milestones/M2/eval-composition.md`: C1–C12 (Q3 composition) and F1–F9 (the Tester's "Fixture
// rules I applied"), plus TAG (composition tags agree with the data), HH (seeded household shape), SUB (the AC-M2-11 and
// AC-M2-25 subsets, PO F3) and READ (the WI-M2-15 reader refuses the files).
//
// Each C rule is checked twice: the Q3 threshold (`.rule`) and the exact value the Tester tabled for PO approval
// (`.pin`), so that any fixture change fails loudly and goes back to the PO (ruling 1). The file hashes are pinned
// separately (`EvalFreezeTests`). The checker is a pure function of the three files' bytes, so every check has a
// negative control on a mutated in-memory copy (`EvalCompositionTests`).

import Foundation
import TendCore
@testable import TendIngestion

// MARK: - SHA-256 (FIPS 180-4), for the PO-approved hash pins and MANIFEST.sha256

/// A small SHA-256 for tests only. `TendIngestion` stays Foundation-only and has no crypto (plan "Fixtures hash");
/// Foundation on Linux has no CryptoKit. Checked against the FIPS 180-4 example vectors.
enum SHA256Hex {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(message[b]) << 24 | UInt32(message[b + 1]) << 16 | UInt32(message[b + 2]) << 8
                    | UInt32(message[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        let digits = Array("0123456789abcdef")
        var out = ""
        for word in h {
            for shift in stride(from: 28, through: 0, by: -4) { out.append(digits[Int((word >> UInt32(shift)) & 0xf)]) }
        }
        return out
    }
}

// MARK: - The real fixture files

enum EvalFixtureFiles {
    static let directory = "Fixtures/M2/eval"
    static let compositionDoc = "docs/milestones/M2/eval-composition.md"
    /// The three Tester-owned files the PO approved (ruling 1).
    static let approvedNames = ["inputs.json", "household.json", "golden.json"]

    static func url(_ name: String) -> URL {
        IngestionSourceScanTests.repositoryRoot().appendingPathComponent(directory).appendingPathComponent(name)
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    static func set() throws -> EvalFixtureSet {
        EvalFixtureSet(inputs: try data("inputs.json"), household: try data("household.json"),
                       golden: try data("golden.json"))
    }
}

/// The three files' bytes. Mutations parse, edit and re-write canonically (`EvalSelfTest.canonical`).
struct EvalFixtureSet {
    var inputs: Data
    var household: Data
    var golden: Data

    /// A copy with each file's JSON value edited by `edit` (in memory only; nothing is written to disk).
    func mutated(_ edit: (inout EvalJSONRoots) -> Void) throws -> EvalFixtureSet {
        var roots = EvalJSONRoots(inputs: try EvalJSONReader.parse(inputs),
                                  household: try EvalJSONReader.parse(household),
                                  golden: try EvalJSONReader.parse(golden))
        edit(&roots)
        return EvalFixtureSet(inputs: try EvalSelfTest.canonical(roots.inputs),
                              household: try EvalSelfTest.canonical(roots.household),
                              golden: try EvalSelfTest.canonical(roots.golden))
    }
}

struct EvalJSONRoots {
    var inputs: EvalJSON
    var household: EvalJSON
    var golden: EvalJSON

    private static func index(_ array: EvalJSON?, where member: String, is value: String) -> Int? {
        guard case let .array(items)? = array else { return nil }
        return items.firstIndex { $0[member] == .string(value) }
    }

    /// Sets a member of the input with this `id` (`/text`, `/mode`, `/composition`).
    mutating func input(_ id: String, _ pointer: String, _ value: EvalJSON?) {
        guard let i = Self.index(inputs["inputs"], where: "id", is: id) else { return }
        inputs = inputs.setting("/inputs/\(i)" + pointer, to: value)
    }

    mutating func inputText(_ id: String, replacing old: String, with new: String) {
        guard let i = Self.index(inputs["inputs"], where: "id", is: id),
              case let .string(text)? = inputs.value(at: "/inputs/\(i)/text") else { return }
        input(id, "/text", .string(text.replacingOccurrences(of: old, with: new)))
    }

    mutating func tags(_ id: String, _ edit: (inout [String]) -> Void) {
        guard let i = Self.index(inputs["inputs"], where: "id", is: id),
              case let .array(values)? = inputs.value(at: "/inputs/\(i)/composition") else { return }
        var tags = values.compactMap { value -> String? in if case let .string(s) = value { s } else { nil } }
        edit(&tags)
        input(id, "/composition", .array(tags.map(EvalJSON.string)))
    }

    /// Sets a member of the golden item with this `key`.
    mutating func item(_ key: String, _ pointer: String, _ value: EvalJSON?) {
        guard let i = Self.index(golden["items"], where: "key", is: key) else { return }
        golden = golden.setting("/items/\(i)" + pointer, to: value)
    }

    /// Sets a member of the seeded task (or room) with this `key`.
    mutating func task(_ key: String, _ pointer: String, _ value: EvalJSON?) {
        guard let i = Self.index(household["tasks"], where: "key", is: key) else { return }
        household = household.setting("/tasks/\(i)" + pointer, to: value)
    }

    mutating func room(_ key: String, _ pointer: String, _ value: EvalJSON?) {
        guard let i = Self.index(household["rooms"], where: "key", is: key) else { return }
        household = household.setting("/rooms/\(i)" + pointer, to: value)
    }

    /// Keeps only the array items for which `keep` is true.
    static func filter(_ root: EvalJSON, _ member: String, _ keep: (EvalJSON) -> Bool) -> EvalJSON {
        guard case let .array(items)? = root[member] else { return root }
        return root.setting("/" + member, to: .array(items.filter(keep)))
    }

    mutating func removeItems(_ keep: (EvalJSON) -> Bool) { golden = Self.filter(golden, "items") { !keep($0) } }

    /// Applies `edit` to every golden item.
    mutating func eachItem(_ edit: (EvalJSON) -> EvalJSON) {
        guard case let .array(items)? = golden["items"] else { return }
        golden = golden.setting("/items", to: .array(items.map(edit)))
    }

    mutating func eachTask(_ edit: (EvalJSON) -> EvalJSON) {
        guard case let .array(items)? = household["tasks"] else { return }
        household = household.setting("/tasks", to: .array(items.map(edit)))
    }
}

// MARK: - The check

struct CompositionViolation: Hashable, CustomStringConvertible {
    enum Kind: String, Hashable { case rule, pin, tag }
    var rule: String
    var kind: Kind
    var detail: String
    var description: String { "\(rule) [\(kind.rawValue)] \(detail)" }
}

/// The values the Tester tabled in `eval-composition.md` (v3) and the PO approved at `95491ed` (ruling 1). Changing one
/// is a fixture change: it goes back to the PO before the freeze, and needs a `DECISIONS.md` entry after it (AC-M2-14).
enum EvalCompositionPins {
    static func ids(_ numbers: [Int]) -> [String] { numbers.map { $0 < 10 ? "in0\($0)" : "in\($0)" } }

    static let inputIDs = ids(Array(1...20))
    static let voice = ids([2, 4, 6, 8, 10, 12, 14, 16, 17, 20])
    static let text = ids([1, 3, 5, 7, 9, 11, 13, 15, 18, 19])
    static let wordCounts = [24, 31, 25, 35, 28, 32, 28, 28, 26, 29, 23, 27, 28, 32, 22, 31, 29, 32, 21, 34]
    static let kindCounts: [TaskKind: Int] = [.oneOff: 36, .recurring: 12, .restock: 10]
    static let weatherItems = 12
    static let weatherInputs = ids([1, 4, 7, 10, 13, 14, 16, 19, 20])
    static let criticalKeys = ["g02-electric", "g05-chicken", "g08-water", "g08-insurance", "g11-smoke", "g11-yogurt",
                               "g18-tax", "g18-soup"]
    static let criticalInputs = ids([2, 5, 8, 11, 18])
    static let deepCleanItems = 6
    static let deepCleanInputs = ids([1, 5, 9, 14, 19])
    static let existingItems = 17
    static let existingInputs = ids([1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 17, 19])
    static let repeatInputs = ids([3, 6, 12, 18])
    static let fillerInputs = voice
    static let selfCorrectionInputs = ids([2, 8, 14, 16, 20])
    static let n = 58
    static let createItems = 41
    static let itemsPerInput = 2...3
    static let newRooms: [String: String] = ["g01-balcony": "Balcony", "g07-patio": "Patio", "g07-shed": "Shed",
                                             "g13-porch": "Porch"]
    static let roomCount = 9
    static let taskCount = 19
    static let states: [String: Int] = ["active": 13, "maintenance": 1, "resurfaced": 1, "deferred": 1, "completed": 3]
    static let maxShortlist = 6
    /// PO follow-up ruling F3: AC-M2-11 = in01 (text), in02, in10 (voice); AC-M2-25 = in08, in16 (voice).
    static let subsets: [String: EvalInputMode] = ["in01": .text, "in02": .voice, "in10": .voice, "in08": .voice,
                                                   "in16": .voice]
}

enum EvalCompositionCheck {
    static let knownTags: Set<String> = ["weather", "critical", "deepClean", "existingTask", "repeat",
                                         "fillerOrCorrection", "newRoom", "completedTaskSaidAgain",
                                         "sameChoreOtherRoom"]
    /// PO ruling 9: weather-dependent = the person ties the chore to the weather (rain, dry, sun).
    static let weatherWords: Set<String> = ["rain", "raining", "dry", "sun", "sunny"]
    static let fillerWords: Set<String> = ["um", "uh"]

    /// Every violation of the three files, in rule order. Empty means the fixtures pass.
    static func violations(_ set: EvalFixtureSet) -> [CompositionViolation] {
        var out: [CompositionViolation] = []
        func failAs(_ rule: String, _ kind: CompositionViolation.Kind, _ detail: String) {
            out.append(CompositionViolation(rule: rule, kind: kind, detail: detail))
        }
        func fail(_ rule: String, _ detail: String) { failAs(rule, .rule, detail) }

        // F2 and F3 read the raw bytes of all three files, members the reader ignores included.
        for (name, data) in [("inputs.json", set.inputs), ("household.json", set.household), ("golden.json", set.golden)] {
            let text = String(decoding: data, as: UTF8.self)
            for run in digitRunsHolding600to729(text) { fail("F2", "\(name): digit run \(run) holds a value 600…729 (N-3)") }
            for match in BannedTokens.matches(in: text) { fail("F3", "\(name): banned token \"\(match.token)\" (UX-3)") }
        }

        let fixtures: EvalFixtures
        let inputsRoot: EvalJSON, goldenRoot: EvalJSON, householdRoot: EvalJSON
        do {
            fixtures = try EvalFixtures(inputs: set.inputs, household: set.household, golden: set.golden)
            inputsRoot = try EvalJSONReader.parse(set.inputs)
            goldenRoot = try EvalJSONReader.parse(set.golden)
            householdRoot = try EvalJSONReader.parse(set.household)
        } catch let error as EvalFixtureError {
            if case .tokenNotKeyword = error { fail("F4", "\(error)") } else { fail("READ", "\(error)") }
            return out
        } catch {
            fail("READ", "\(error)")
            return out
        }

        let P = EvalCompositionPins.self
        let inputs = fixtures.inputs
        let golden = fixtures.golden
        let tags = compositionTags(inputsRoot)
        let phrases = referencePhrases(goldenRoot)
        func inputsWith(_ predicate: (EvalGoldenItem) -> Bool) -> [String] {
            inputs.map(\.id).filter { id in golden.contains { $0.inputID == id && predicate($0) } }
        }
        func tagged(_ tag: String) -> [String] { inputs.map(\.id).filter { tags[$0, default: []].contains(tag) } }
        func checkTag(_ rule: String, _ tag: String, equals derived: [String]) {
            if tagged(tag) != derived { failAs(rule, .tag, "\"\(tag)\" tags \(tagged(tag)) ≠ data \(derived)") }
        }

        // C1: 20 inputs, in01…in20 in order.
        if inputs.count != 20 { fail("C1", "\(inputs.count) inputs, Q3 needs 20") }
        if inputs.map(\.id) != P.inputIDs { failAs("C1", .pin, "input IDs \(inputs.map(\.id))") }

        // C2, C3: ≥ 8 voice and ≥ 8 text.
        let voice = inputs.filter { $0.mode == .voice }.map(\.id)
        let text = inputs.filter { $0.mode == .text }.map(\.id)
        if voice.count < 8 { fail("C2", "\(voice.count) voice inputs, Q3 needs ≥ 8") }
        if voice != P.voice { failAs("C2", .pin, "voice inputs \(voice)") }
        if text.count < 8 { fail("C3", "\(text.count) text inputs, Q3 needs ≥ 8") }
        if text != P.text { failAs("C3", .pin, "text inputs \(text)") }

        // C4: 10–80 whitespace-split words each.
        let words = inputs.map { $0.text.split(whereSeparator: \.isWhitespace).count }
        for (input, count) in zip(inputs, words) where !(10...80).contains(count) {
            fail("C4", "\(input.id) has \(count) words, Q3 needs 10–80")
        }
        if words != P.wordCounts { failAs("C4", .pin, "word counts \(words)") }

        // C5: all four item types (one-off, recurring, restock, weather-dependent).
        var kinds: [TaskKind: Int] = [:]
        for item in golden { kinds[item.kind, default: 0] += 1 }
        for kind in [TaskKind.oneOff, .recurring, .restock] where kinds[kind, default: 0] == 0 {
            fail("C5", "no \(kind) item")
        }
        let weatherItems = golden.filter(\.isWeatherDependent).count
        if weatherItems == 0 { fail("C5", "no weather-dependent item") }
        if kinds != P.kindCounts || weatherItems != P.weatherItems {
            failAs("C5", .pin, "kinds \(kinds), weather items \(weatherItems)")
        }

        // C6: ≥ 5 inputs with a weather condition.
        let weatherInputs = inputsWith(\.isWeatherDependent)
        if weatherInputs.count < 5 { fail("C6", "\(weatherInputs.count) weather inputs, Q3 needs ≥ 5") }
        if weatherInputs != P.weatherInputs || weatherItems != P.weatherItems {
            failAs("C6", .pin, "weather inputs \(weatherInputs), items \(weatherItems)")
        }
        checkTag("C6", "weather", equals: weatherInputs)

        // C7: ≥ 3 critical inputs (bill, expiring food).
        let criticalInputs = inputsWith(\.isCritical)
        let criticalKeys = golden.filter(\.isCritical).map(\.key)
        if criticalInputs.count < 3 { fail("C7", "\(criticalInputs.count) critical inputs, Q3 needs ≥ 3") }
        if criticalKeys != P.criticalKeys || criticalInputs != P.criticalInputs {
            failAs("C7", .pin, "critical items \(criticalKeys)")
        }
        checkTag("C7", "critical", equals: criticalInputs)

        // C8: ≥ 3 deep-clean inputs.
        let deepInputs = inputsWith(\.isDeepClean)
        let deepItems = golden.filter(\.isDeepClean).count
        if deepInputs.count < 3 { fail("C8", "\(deepInputs.count) deep-clean inputs, Q3 needs ≥ 3") }
        if deepInputs != P.deepCleanInputs || deepItems != P.deepCleanItems {
            failAs("C8", .pin, "deep-clean inputs \(deepInputs), items \(deepItems)")
        }
        checkTag("C8", "deepClean", equals: deepInputs)

        // C9: ≥ 5 inputs mentioning an existing task.
        let isExisting: (EvalGoldenItem) -> Bool = { if case .existing = $0.expect { true } else { false } }
        let existingInputs = inputsWith(isExisting)
        let existingItems = golden.filter(isExisting).count
        if existingInputs.count < 5 { fail("C9", "\(existingInputs.count) existing-task inputs, Q3 needs ≥ 5") }
        if existingInputs != P.existingInputs || existingItems != P.existingItems
            || golden.count - existingItems != P.createItems {
            failAs("C9", .pin, "existing-task inputs \(existingInputs), items \(existingItems)")
        }
        checkTag("C9", "existingTask", equals: existingInputs)

        // C10: ≥ 3 inputs with a repeat; each tagged input says the same word of every match group of one golden item twice.
        let repeats = tagged("repeat")
        if repeats.count < 3 { fail("C10", "\(repeats.count) repeat inputs, Q3 needs ≥ 3") }
        if repeats != P.repeatInputs { failAs("C10", .pin, "repeat inputs \(repeats)") }
        for id in repeats {
            guard let input = fixtures.input(id) else { continue }
            let counts = tokenCounts(input.text)
            let said = golden.filter { $0.inputID == id }.contains { item in
                item.matchGroups.allSatisfy { group in group.contains { counts[$0, default: 0] >= 2 } }
            }
            if !said { failAs("C10", .tag, "\(id) is tagged repeat but says no golden item's chore twice") }
        }

        // C11: ≥ 4 inputs with filler or a self-correction; the tag agrees with the filler words.
        let filler = tagged("fillerOrCorrection")
        if filler.count < 4 { fail("C11", "\(filler.count) filler/self-correction inputs, Q3 needs ≥ 4") }
        if filler != P.fillerInputs { failAs("C11", .pin, "filler inputs \(filler)") }
        let saysFiller = inputs.filter { !fillerWords.isDisjoint(with: tokenCounts($0.text).keys) }.map(\.id)
        if saysFiller != filler { failAs("C11", .tag, "inputs with um/uh \(saysFiller) ≠ tagged \(filler)") }
        let corrections = inputs.filter {
            let lower = $0.text.lowercased()
            return lower.contains("no wait") || lower.contains(", no,")
        }.map(\.id)
        if corrections != P.selfCorrectionInputs { failAs("C11", .pin, "self-corrections \(corrections)") }

        // C12: N ≥ 50, ≥ 1 per input.
        if golden.count < 50 { fail("C12", "N = \(golden.count), Q3 needs ≥ 50") }
        for input in inputs where !golden.contains(where: { $0.inputID == input.id }) {
            fail("C12", "\(input.id) has no golden item")
        }
        let perInput = inputs.map { input in golden.filter { $0.inputID == input.id }.count }
        if golden.count != P.n || !perInput.allSatisfy(P.itemsPerInput.contains) {
            failAs("C12", .pin, "N = \(golden.count), per input \(perInput)")
        }

        // TAG: only known tags; newRoom and completedTaskSaidAgain agree with the data.
        for (id, list) in tags.sorted(by: { $0.key < $1.key }) {
            for tag in list where !knownTags.contains(tag) { fail("TAG", "\(id): unknown tag \"\(tag)\"") }
        }
        for id in tagged("newRoom") where !golden.contains(where: {
            guard $0.inputID == id, case .new = $0.room else { return false }
            return true
        }) {
            failAs("TAG", .tag, "\(id) is tagged newRoom but has no new-room item")
        }
        let completed = fixtures.tasks.filter(\.isCompleted)
        for id in tagged("completedTaskSaidAgain") where !golden.contains(where: { item in
            item.inputID == id && item.expect == .create && completed.contains { task in
                EvalScorer.satisfies(Keywords.of(phrases[item.key] ?? ""), groups: task.matchGroups)
            }
        }) {
            failAs("TAG", .tag, "\(id) is tagged completedTaskSaidAgain but no create item repeats a completed task")
        }

        // HH: the seeded household as tabled; the non-active targets are used.
        let states = stateCounts(householdRoot)
        if fixtures.rooms.count != P.roomCount || fixtures.tasks.count != P.taskCount || states != P.states {
            failAs("HH", .pin, "\(fixtures.rooms.count) rooms, \(fixtures.tasks.count) tasks, states \(states)")
        }

        // SUB: the fixed AC-M2-11 and AC-M2-25 subsets exist with their modes (PO F3).
        for (id, mode) in P.subsets.sorted(by: { $0.key < $1.key }) where fixtures.input(id)?.mode != mode {
            failAs("SUB", .pin, "\(id) must be a \(mode) input (PO F3)")
        }

        // F1: every fixture UUID is version 4 with the RFC variant, so `EvalIDGenerator` (version 8) never yields one.
        for (key, id) in fixtures.rooms.map({ ($0.key, $0.id) }) + fixtures.tasks.map({ ($0.key, $0.task.id) }) {
            let bytes = id.uuid
            if bytes.6 >> 4 != 4 || bytes.8 & 0xC0 != 0x80 {
                fail("F1", "\(key) \(id.uuidString) is not a version-4 RFC UUID")
            }
        }

        // F5: distinguishable targets. The reference phrase is words of the input; as a draft text its best target is
        // the item itself (create) or its seeded task (existing).
        for item in golden {
            guard let phrase = phrases[item.key], !phrase.isEmpty else {
                fail("F5", "\(item.key) has no referencePhrase")
                continue
            }
            guard let input = fixtures.input(item.inputID), input.text.contains(phrase) else {
                fail("F5", "\(item.key): referencePhrase is not words of \(item.inputID)")
                continue
            }
            let expected: EvalTarget
            switch item.expect {
            case .create: expected = .golden(item.key)
            case let .existing(seededKey): expected = .seeded(seededKey)
            }
            let best = bestTarget(phrase, golden: golden.filter { $0.inputID == item.inputID }, tasks: fixtures.tasks)
            if best != expected { fail("F5", "\(item.key): best target \(best.map(\.description) ?? "none"), expected \(expected)") }
        }

        // F6: every existing-task mention is reachable on every path; the word-match floor causes no false merge.
        let household = fixtures.household
        for input in inputs {
            let shortlist = DuplicateShortlist.entries(for: input.text, in: household)
            if shortlist.count >= DuplicateShortlist.limit {
                fail("F6", "\(input.id): shortlist has \(shortlist.count) entries, so the cap of 10 may cut")
            } else if shortlist.count > P.maxShortlist {
                failAs("F6", .pin, "\(input.id): shortlist has \(shortlist.count) entries (tabled ≤ \(P.maxShortlist))")
            }
            for item in golden where item.inputID == input.id {
                switch item.expect {
                case let .existing(seededKey):
                    guard let task = fixtures.tasks.first(where: { $0.key == seededKey }) else { continue }
                    if task.isCompleted { fail("F6", "\(item.key): target \(seededKey) is completed (said again = new)") }
                    if !shortlist.contains(where: { $0.taskID == task.task.id }) {
                        fail("F6", "\(item.key): \(seededKey) is not on \(input.id)'s duplicate shortlist")
                    }
                case .create:
                    let room = draftRoom(item.room, fixtures: fixtures)
                    if let hit = LocalWordMatch.target(title: phrases[item.key] ?? "", room: room, in: household) {
                        let key = fixtures.taskKeys[hit] ?? hit.uuidString
                        fail("F6", "\(item.key): the local word-match floor merges it into \(key)")
                    }
                }
            }
        }

        // F7: an existing item's golden fields equal its seeded task.
        for item in golden {
            guard case let .existing(seededKey) = item.expect,
                  let seeded = fixtures.tasks.first(where: { $0.key == seededKey })?.task else { continue }
            let roomKey = seeded.roomID.flatMap { id in fixtures.rooms.first { $0.id == id }?.key }
            let room: EvalGoldenItem.ExpectedRoom = roomKey.map { .existing(roomKey: $0) } ?? .none
            if item.kind != seeded.kind || item.room != room || item.effort != seeded.effort
                || item.isCritical != seeded.isCritical || item.isDeepClean != seeded.isDeepClean
                || item.isWeatherDependent != seeded.isWeatherDependent {
                fail("F7", "\(item.key): golden fields differ from \(seededKey)")
            }
        }

        // F8: rooms (PO ruling 2). existing(room) only when the input says the room's name; a new room is named in the
        // input and is not one of the household's rooms.
        for item in golden {
            let said = Set(Keywords.of(fixtures.input(item.inputID)?.text ?? ""))
            switch item.room {
            case let .existing(roomKey):
                let name = fixtures.rooms.first { $0.key == roomKey }?.name ?? ""
                if !Set(Keywords.of(name)).isSubset(of: said) {
                    fail("F8", "\(item.key): room \(name) is not named in \(item.inputID)")
                }
            case let .new(name, _):
                if fixtures.rooms.contains(where: { TextFolding.foldName($0.name) == TextFolding.foldName(name) }) {
                    fail("F8", "\(item.key): new room \"\(name)\" is an existing room")
                }
                if Keywords.of(name).isEmpty || !Set(Keywords.of(name)).isSubset(of: said) {
                    fail("F8", "\(item.key): new room \"\(name)\" is not named in \(item.inputID)")
                }
                if P.newRooms[item.key] != name { failAs("F8", .pin, "\(item.key): new room \"\(name)\"") }
            case .none:
                break
            }
        }
        let newRoomKeys = Set(golden.filter { if case .new = $0.room { true } else { false } }.map(\.key))
        if newRoomKeys != Set(P.newRooms.keys) { failAs("F8", .pin, "new-room items \(newRoomKeys.sorted())") }

        // F9: effort (PO ruling 5): a deep clean is high. Ruling 9 and Q3: the flags follow the person's words.
        for item in golden {
            let said = Set(Keywords.of(phrases[item.key] ?? ""))
            if item.isDeepClean && item.effort != .high { fail("F9", "\(item.key): a deep clean must be high effort") }
            if item.isWeatherDependent != !said.isDisjoint(with: weatherWords) {
                fail("F9", "\(item.key): weather-dependent \(item.isWeatherDependent) but the phrase "
                     + (said.isDisjoint(with: weatherWords) ? "ties it to no weather" : "ties it to the weather"))
            }
            if item.isDeepClean != said.contains("deep") {
                fail("F9", "\(item.key): deep clean \(item.isDeepClean) disagrees with the phrase")
            }
        }
        return out
    }

    // MARK: Helpers

    /// Each maximal run of ASCII digits that has a substring whose value is 600…729. Such a substring, without its
    /// leading zeros, is exactly three digits starting at a non-zero digit, so a 3-digit window suffices.
    static func digitRunsHolding600to729(_ text: String) -> [String] {
        var hits: [String] = []
        var run: [UInt8] = []
        func flush() {
            if run.count >= 3 {
                for i in 0...(run.count - 3) where run[i] != 0x30 {
                    let value = Int(run[i] - 0x30) * 100 + Int(run[i + 1] - 0x30) * 10 + Int(run[i + 2] - 0x30)
                    if (600...729).contains(value) { hits.append(String(decoding: run, as: UTF8.self)); break }
                }
            }
            run.removeAll()
        }
        for byte in text.utf8 { if (0x30...0x39).contains(byte) { run.append(byte) } else { flush() } }
        flush()
        return hits
    }

    /// Lower-cased letter-or-digit tokens with their counts (stop words kept: "um" and "uh" are stop words).
    static func tokenCounts(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            counts[String(token), default: 0] += 1
        }
        return counts
    }

    static func compositionTags(_ root: EvalJSON) -> [String: [String]] {
        guard case let .array(items)? = root["inputs"] else { return [:] }
        var result: [String: [String]] = [:]
        for item in items {
            guard case let .string(id)? = item["id"] else { continue }
            if case let .array(values)? = item["composition"] {
                result[id] = values.compactMap { if case let .string(s) = $0 { s } else { nil } }
            } else {
                result[id] = []
            }
        }
        return result
    }

    static func referencePhrases(_ root: EvalJSON) -> [String: String] {
        guard case let .array(items)? = root["items"] else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            if case let .string(key)? = item["key"], case let .string(phrase)? = item["referencePhrase"] {
                result[key] = phrase
            }
        }
        return result
    }

    static func stateCounts(_ root: EvalJSON) -> [String: Int] {
        guard case let .array(items)? = root["tasks"] else { return [:] }
        var result: [String: Int] = [:]
        for case let .string(state)? in items.map({ $0["state"] }) { result[state, default: 0] += 1 }
        return result
    }

    /// The scorer's own best-target rule (`EvalScorer.bestTarget`) over the input's targets, with the phrase's
    /// keywords as the draft text.
    static func bestTarget(_ phrase: String, golden: [EvalGoldenItem], tasks: [EvalSeededTask]) -> EvalTarget? {
        let draft = DraftRecord(
            draftID: 1, title: "", kind: .oneOff, room: .none, effort: .normal, isCritical: false, isDeepClean: false,
            isWeatherDependent: false, allowedDayparts: [], allowedWeekdays: [],
            windowStart: EvalInstant(millisecondsSince1970: 0), windowEnd: EvalInstant(millisecondsSince1970: 0),
            recurrenceIntervalDays: nil, sourcePhrase: phrase, duplicate: .none
        )
        return EvalScorer.bestTarget(for: draft, text: EvalScorer.draftText(of: draft),
                                     targets: EvalScorer.targets(golden: golden, tasks: tasks)).target
    }

    static func draftRoom(_ room: EvalGoldenItem.ExpectedRoom, fixtures: EvalFixtures) -> DraftRoom {
        switch room {
        case let .existing(roomKey):
            fixtures.rooms.first { $0.key == roomKey }.map { .existing($0.id) } ?? .none
        case let .new(name, _): .proposed(name)
        case .none: .none
        }
    }
}

// MARK: - MANIFEST.sha256 (AC-M2-14 freeze; plan "Fixtures hash")

/// The manifest is `sha256sum` output for every file in `Fixtures/M2/eval` except the manifest itself, in C-locale name
/// order. Documented command (run by whoever freezes, after the owner's L2a and the PO conditions of ruling 1):
///
///     cd Fixtures/M2/eval && LC_ALL=C sha256sum golden.json household.json inputs.json results-v1.schema.json > MANIFEST.sha256
///
/// (On a Mac without `sha256sum`, `shasum -a 256` with the same arguments writes the same format.) The fixtures hash the
/// scorer and `TendEval` use is the SHA-256 of the manifest's bytes (plan "Fixtures hash").
enum EvalManifest {
    static let name = "MANIFEST.sha256"
    static let command = "cd Fixtures/M2/eval && LC_ALL=C sha256sum golden.json household.json inputs.json "
        + "results-v1.schema.json > MANIFEST.sha256"

    /// The files a manifest of `directory` must list: every regular file except the manifest, in byte order.
    static func listedNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 != name && !$0.hasPrefix(".") }
            .sorted { TextFolding.utf8Precedes($0, $1) }
    }

    /// The manifest text the documented command writes, from the files' bytes.
    static func render(_ files: [(name: String, data: Data)]) -> String {
        files.sorted { TextFolding.utf8Precedes($0.name, $1.name) }
            .map { "\(SHA256Hex.hex($0.data))  \($0.name)\n" }.joined()
    }

    /// Every reason `manifest` does not verify against `files` (empty = verifies): one line per file, format
    /// `<64 lower-case hex><two spaces><name>\n`, names unique and in byte order, exactly the expected names, each hash
    /// equal to the file's.
    static func problems(_ manifest: String, files: [(name: String, data: Data)]) -> [String] {
        var problems: [String] = []
        guard manifest.hasSuffix("\n") else { return ["the manifest does not end with a newline"] }
        var names: [String] = []
        for line in manifest.dropLast().split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[1].isEmpty, parts[0].count == 64,
                  parts[0].allSatisfy({ "0123456789abcdef".contains($0) }), !parts[2].isEmpty else {
                problems.append("malformed line: \(line)")
                continue
            }
            let name = String(parts[2])
            names.append(name)
            guard let file = files.first(where: { $0.name == name }) else {
                problems.append("lists \(name), which is not a fixture file")
                continue
            }
            if SHA256Hex.hex(file.data) != String(parts[0]) { problems.append("hash of \(name) does not match") }
        }
        if names != names.sorted(by: { TextFolding.utf8Precedes($0, $1) }) || Set(names).count != names.count {
            problems.append("names are not unique and in byte order: \(names)")
        }
        for file in files where !names.contains(file.name) { problems.append("does not list \(file.name)") }
        return problems
    }

    /// The `- **Status:**` bullet of the Tester's composition document, with its continuation lines.
    static func compositionStatus() throws -> String {
        let url = IngestionSourceScanTests.repositoryRoot().appendingPathComponent(EvalFixtureFiles.compositionDoc)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("- **Status:**") }) else { return "" }
        var status = [String(lines[start])]
        for line in lines[(start + 1)...] {
            guard line.hasPrefix("  ") else { break }
            status.append(String(line))
        }
        return status.joined(separator: "\n")
    }
}
