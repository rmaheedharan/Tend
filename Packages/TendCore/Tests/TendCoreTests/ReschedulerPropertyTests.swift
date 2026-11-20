// Gate properties of gentle rescheduling (AC-M1-20, AC-M1-21, AC-M1-22; FR-B1, FR-B2, UX-3, UX-2; design D-2, D-3;
// review W3-F2).
// - AC-M1-20: a task whose window ends 60 times in a row keeps the same decoded structure; only its window moves.
// - AC-M1-21: one pass over 500 seeded households equals the independent R0–R4 oracle and leaves no ended window.
// - AC-M1-22: the same inputs always give the same outputs.
// Failure messages name the seed so a case can be replayed.

import Foundation
import Testing
import TendCore

@Suite("Rescheduler gate properties (AC-M1-20, AC-M1-21, AC-M1-22)")
struct ReschedulerPropertyTests {

    // MARK: AC-M1-20 structure after N passes

    enum RuleType: String, CaseIterable, Sendable {
        case r2DeepClean = "R2 deep clean"
        case r3Critical = "R3 critical"
        case r4Other = "R4 other"
    }

    /// The decoded structure of a household holding one task (AC-M1-20, review T-08): every key path, the encoded
    /// values of every non-window field, every collection's count, and the window duration as a bit pattern.
    struct Structure: Equatable {
        var keyPaths: Set<String>
        var nonWindowValues: Data
        var collectionCounts: [String: Int]
        var durationBits: UInt64
        var decodedTask: HouseholdTask
    }

    static func keyPaths(of value: Any, prefix: String) -> Set<String> {
        var paths: Set<String> = []
        if let object = value as? [String: Any] {
            for (key, child) in object {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                paths.insert(path)
                paths.formUnion(keyPaths(of: child, prefix: path))
            }
        } else if let array = value as? [Any] {
            for child in array { paths.formUnion(keyPaths(of: child, prefix: prefix + "[]")) }
        }
        return paths
    }

    static func collectionCounts(of value: Any, prefix: String, into counts: inout [String: Int]) {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                collectionCounts(of: child, prefix: prefix.isEmpty ? key : "\(prefix).\(key)", into: &counts)
            }
        } else if let array = value as? [Any] {
            counts[prefix, default: 0] += array.count
            for child in array { collectionCounts(of: child, prefix: prefix + "[]", into: &counts) }
        }
    }

    static func structure(of task: HouseholdTask, room: Room) throws -> Structure {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Household(tasks: [task], rooms: [room]))
        let decoded = try JSONDecoder().decode(Household.self, from: data)
        let decodedTask = try #require(decoded.tasks.first)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var counts: [String: Int] = [:]
        collectionCounts(of: object, prefix: "", into: &counts)
        var tasks = try #require(object["tasks"] as? [[String: Any]])
        tasks[0]["windowStart"] = nil
        tasks[0]["windowEnd"] = nil
        var nonWindow = object
        nonWindow["tasks"] = tasks
        let nonWindowValues = try JSONSerialization.data(withJSONObject: nonWindow, options: [.sortedKeys])
        return Structure(
            keyPaths: keyPaths(of: object, prefix: ""),
            nonWindowValues: nonWindowValues,
            collectionCounts: counts,
            durationBits: decodedTask.windowEnd.timeIntervalSince(decodedTask.windowStart).bitPattern,
            decodedTask: decodedTask
        )
    }

    /// A task of `rule`'s type whose window ended at (or before) `now`, in a start state that rule accepts.
    static func endedTask(rule: RuleType, kind: TaskKind, now: Date, using rng: inout SplitMix64,
                          duration: TimeInterval? = nil) throws -> HouseholdTask {
        let isDeepClean = rule == .r2DeepClean
        let isCritical = rule == .r3Critical
        var states: [TaskState] = [.active, .deferred(until: now.addingTimeInterval(-rng.nextUnitInterval() * 86_400))]
        if isDeepClean { states.append(.maintenance) }
        if isCritical { states.append(.resurfaced) }
        let duration = duration ?? HouseholdGenerator.positiveDuration(using: &rng)
        let end = rng.chance(0.5) ? now : now.addingTimeInterval(-HouseholdGenerator.positiveDuration(using: &rng))
        return try HouseholdTask(
            id: HouseholdGenerator.uuid(using: &rng),
            title: HouseholdGenerator.titles[Int.random(in: 0..<HouseholdGenerator.titles.count, using: &rng)],
            kind: kind,
            roomID: rng.chance(0.7) ? Fixtures.kitchenID : nil,
            effort: Effort.allCases[Int.random(in: 0..<Effort.allCases.count, using: &rng)],
            isCritical: isCritical,
            isDeepClean: isDeepClean,
            isWeatherDependent: rng.chance(0.3),
            allowedDayparts: HouseholdGenerator.nonEmptySubset(of: Daypart.allCases, using: &rng),
            allowedWeekdays: HouseholdGenerator.nonEmptySubset(of: Weekday.allCases, using: &rng),
            windowStart: end.addingTimeInterval(-duration),
            windowEnd: end,
            recurrenceIntervalDays: kind == .recurring ? Int.random(in: 1...30, using: &rng) : nil,
            state: states[Int.random(in: 0..<states.count, using: &rng)],
            completedAt: rng.chance(0.5) ? now.addingTimeInterval(-86_400 * 3.5) : nil
        )
    }

    /// Runs `passes` consecutive passes: the first at `firstNow` (at or after the ended window), then each time `now`
    /// advances to the task's current `windowEnd` (AC-M1-20).
    static func structures(
        of task: HouseholdTask, from firstNow: Date, passes: Int, zone: TimeZone, room: Room
    ) throws -> [(now: Date, task: HouseholdTask, structure: Structure)] {
        let calendar = SelectionFixtures.gregorian(in: zone)
        var current = task
        var now = firstNow
        var result: [(now: Date, task: HouseholdTask, structure: Structure)] = []
        for _ in 1...passes {
            current = Rescheduler.reschedule(current, at: now, calendar: calendar, timeZone: zone).task
            result.append((now, current, try structure(of: current, room: room)))
            now = current.windowEnd
        }
        return result
    }

    static let room = Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: Fixtures.referenceDate)

    @Test("AC-M1-20 (Gate): after N = 1…60 consecutive ended windows the decoded structure equals the structure after 1 pass; only the window moves")
    func structureDoesNotGrow() throws {
        let seeds: ClosedRange<UInt64> = 600_001...600_040
        var chains = 0
        var comparisons = 0
        var movedBy: TimeInterval = 0
        for seed in seeds {
            var rng = SplitMix64(seed: seed)
            let zone = try SelectionFixtures.zone(
                SelectionCorpus.zoneIdentifiers[Int.random(in: 0..<SelectionCorpus.zoneIdentifiers.count, using: &rng)])
            let now = HouseholdGenerator.defaultNow.addingTimeInterval(
                Double(Int.random(in: -86_400 * 365...86_400 * 365, using: &rng)) + rng.nextUnitInterval())
            for rule in RuleType.allCases {
                for kind in TaskKind.allCases {
                    let task = try Self.endedTask(rule: rule, kind: kind, now: now, using: &rng)
                    let runs = try Self.structures(of: task, from: now, passes: 60, zone: zone, room: Self.room)
                    let first = runs[0].structure
                    let label = "seed \(seed), \(rule.rawValue), \(kind), \(zone.identifier)"
                    let expectedState: TaskState = switch rule {
                    case .r2DeepClean: .maintenance
                    case .r3Critical: .resurfaced
                    case .r4Other: .active
                    }
                    for (index, run) in runs.enumerated() {
                        let n = index + 1
                        #expect(run.structure.keyPaths == first.keyPaths, "N = \(n), \(label): encoded keys")
                        #expect(run.structure.nonWindowValues == first.nonWindowValues,
                                "N = \(n), \(label): non-window values")
                        #expect(run.structure.collectionCounts == first.collectionCounts,
                                "N = \(n), \(label): collection counts")
                        #expect(run.structure.durationBits == first.durationBits,
                                "N = \(n), \(label): windowEnd - windowStart differs from pass 1 (bit pattern)")
                        #expect(run.structure.decodedTask == run.task, "N = \(n), \(label): decode round trip")
                        #expect(run.task.state == expectedState, "N = \(n), \(label)")
                        #expect(run.task.windowEnd > run.now, "N = \(n), \(label): the new window has not ended")
                        comparisons += 1
                    }
                    movedBy = max(movedBy, runs[59].task.windowEnd.timeIntervalSince(task.windowEnd))
                    chains += 1
                }
            }
        }
        print("AC-M1-20: seeds \(seeds), \(chains) chains (R2, R3, R4 x one-off, recurring, restock), "
              + "\(comparisons) pass comparisons against pass 1 (N = 1...60), duration compared by bit pattern, "
              + "longest chain moved \(Int(movedBy / 86_400)) days")
        #expect(chains == seeds.count * 9)
    }

    /// 2^30 s after the 2001 reference date: 2035-01-10 13:37:04Z. Above it the `Double` grid of `Date` doubles from
    /// 2^-23 s to 2^-22 s (review W3-F2).
    static let binadeEdge = Date(timeIntervalSinceReferenceDate: 1_073_741_824)

    /// Review W3-F2, measured (open PO question Q21 in dev-notes; AC-M1-20 is not changed). Below 2^30 s a `Date` is
    /// a multiple of 2^-23 s, above it of 2^-22 s. A duration that is an odd number of 2^-23 s steps cannot be kept
    /// once `s + D` lands on the coarser grid, so `windowEnd - windowStart` changes once by exactly one 2^-23 s step
    /// (about 119 ns): at the pass whose window first reaches the edge, or at the next one (when that pass's `s` is the
    /// first start above the edge). This test pins that behaviour exactly, so any further drift fails: exactly one
    /// change, at one of those two passes, by exactly one step, and the duration is bit-identical before and after
    /// it; every other part of the structure is identical for all N. The AC-M1-20 gate test above keeps its
    /// strict bit-pattern comparison over its corpus (2024–2029), which crosses no edge.
    @Test("W3-F2 measurement: across 2035-01-10 13:37:04Z (2^30 s) the window duration changes at most once, by exactly one 2^-23 s rounding step, then never again; structure otherwise identical")
    func structureAcrossBinadeEdge() throws {
        let fineStep = (Self.binadeEdge.timeIntervalSinceReferenceDate - 1).ulp
        #expect(fineStep == 0x1p-23 && Self.binadeEdge.timeIntervalSinceReferenceDate.ulp == 0x1p-22)
        var report: [String] = []
        var crossings = 0
        for seed in UInt64(610_001)...610_012 {
            var rng = SplitMix64(seed: seed)
            let zone = try SelectionFixtures.zone(
                SelectionCorpus.zoneIdentifiers[Int.random(in: 0..<SelectionCorpus.zoneIdentifiers.count, using: &rng)])
            let start = Self.binadeEdge.addingTimeInterval(-Double(Int.random(in: 20...40, using: &rng)) * 86_400)
            // A week-long window whose fractional part is an odd multiple of the fine grid (2^-23 s), so the coarse grid
            // above the edge (2^-22 s) cannot always hold `s + D`.
            let fineSteps = 2 * Int.random(in: 0..<(1 << 21), using: &rng) + 1
            let duration = 7 * 86_400 + Double(fineSteps) * fineStep
            for rule in RuleType.allCases {
                let task = try Self.endedTask(rule: rule, kind: .recurring, now: start, using: &rng, duration: duration)
                let runs = try Self.structures(of: task, from: start, passes: 60, zone: zone, room: Self.room)
                let label = "seed \(seed), \(rule.rawValue)"
                #expect(runs[0].task.windowEnd < Self.binadeEdge && runs[59].task.windowStart > Self.binadeEdge,
                        "\(label): the chain must cross the edge")
                crossings += 1
                let first = runs[0].structure
                // The pass whose window first reaches the edge.
                let edgePass = try #require(runs.firstIndex { $0.task.windowEnd >= Self.binadeEdge })
                for (index, run) in runs.enumerated() {
                    let n = index + 1
                    #expect(run.structure.keyPaths == first.keyPaths, "\(label), N = \(n): encoded keys")
                    #expect(run.structure.nonWindowValues == first.nonWindowValues, "\(label), N = \(n): values")
                    #expect(run.structure.collectionCounts == first.collectionCounts, "\(label), N = \(n): counts")
                }
                let durations = runs.map { Double(bitPattern: $0.structure.durationBits) }
                let changes = durations.indices.dropFirst().filter { durations[$0] != durations[$0 - 1] }
                // Only a duration that is an odd number of fine steps does not fit the coarse grid.
                let isOddSteps = (durations[0] / fineStep).truncatingRemainder(dividingBy: 2) == 1
                #expect(changes.count == (isOddSteps ? 1 : 0),
                        "\(label): \(isOddSteps ? "exactly one change" : "no change"), saw passes \(changes.map { $0 + 1 })")
                if let change = changes.first {
                    #expect(change == edgePass || change == edgePass + 1,
                            "\(label): the change is at the edge pass N = \(edgePass + 1) or the next, not N = \(change + 1)")
                    #expect(abs(durations[change] - durations[change - 1]) == fineStep,
                            "\(label): the change is exactly one fine step")
                    report.append("\(label): N = \(change + 1), "
                                  + "\(durations[change] > durations[change - 1] ? "+" : "-")1 step")
                }
            }
        }
        print("W3-F2 measurement: \(crossings) chains cross \(Self.binadeEdge) (2^30 s); one step = \(fineStep) s; "
              + "\(report.count) chains change their duration once, by one step: " + report.joined(separator: "; "))
        #expect(!report.isEmpty, "the case must exercise the rounding it documents")
    }

    // MARK: AC-M1-21 one pass over 500 households

    @Test("AC-M1-21 (Gate): over 500 seeded households of 50-500 tasks (at least half with ended windows) one pass equals the oracle, leaves no ended window, and is idempotent")
    func gatePass() throws {
        let corpus = try SelectionCorpus.reschedule.get()
        var taskCount = 0
        var minTasks = Int.max
        var maxTasks = 0
        var ended = 0
        var endsAtNow = 0
        var restOverEnded = 0
        var restingEnded = 0
        var completedEnded = 0
        var outcomes: [RescheduleOutcome: Int] = [:]
        var selectionSizes = [0, 0, 0, 0]
        for testCase in corpus {
            let moment = testCase.moment
            let now = moment.now
            let before = testCase.household
            let label = testCase.description
            let tasks = before.tasks
            minTasks = min(minTasks, tasks.count)
            maxTasks = max(maxTasks, tasks.count)
            taskCount += tasks.count
            let endedHere = tasks.filter { $0.windowEnd <= now }.count
            #expect(endedHere * 2 >= tasks.count, "seed \(testCase.seed): at least half the windows have ended")
            ended += endedHere
            for task in tasks where task.windowEnd <= now {
                if task.windowEnd == now { endsAtNow += 1 }
                switch task.state {
                case .deferred(let until): if until <= now { restOverEnded += 1 } else { restingEnded += 1 }
                case .completed: completedEnded += 1
                default: break
                }
            }

            let after = Rescheduler.reschedule(before, at: now, calendar: moment.calendar, timeZone: moment.timeZone)
            #expect(after.rooms == before.rooms && after.schemaVersion == before.schemaVersion, "seed \(testCase.seed)")
            #expect(after.tasks.count == before.tasks.count, "seed \(testCase.seed)")
            for (old, new) in zip(before.tasks, after.tasks) {
                let resting = { if case .deferred(let until) = old.state { return until > now } else { return false } }()
                // (a) nothing that can be offered keeps an ended window.
                if new.state != .completed && !resting {
                    #expect(new.windowEnd > now, "(a) seed \(testCase.seed), task \(old.id): \(label)")
                }
                // (b) no deferral whose rest is over remains.
                if case .deferred(let until) = new.state {
                    #expect(until > now, "(b) seed \(testCase.seed), task \(old.id)")
                }
                // (c) completed and resting tasks are unchanged field for field.
                if old.state == .completed || resting {
                    #expect(new == old, "(c) seed \(testCase.seed), task \(old.id)")
                }
                // (d) the independent oracle.
                #expect(new == (try RescheduleOracle.rescheduled(old, at: now, calendar: moment.calendar)),
                        "(d) seed \(testCase.seed), task \(old.id): \(label)")
                let outcome = Rescheduler.reschedule(old, at: now, calendar: moment.calendar,
                                                     timeZone: moment.timeZone).outcome
                outcomes[outcome, default: 0] += 1
            }
            // (e) a second pass at the same now changes nothing.
            #expect(Rescheduler.reschedule(after, at: now, calendar: moment.calendar, timeZone: moment.timeZone) == after,
                    "(e) seed \(testCase.seed)")
            // (f) the Rule of Three still holds on the result (AC-M1-14, AC-M1-15, with AC-M1-16 order).
            let selection = NowSelector.select(from: after, in: moment)
            let expected = ContextOracle.expectedSelection(from: after.tasks, in: ContextOracle.Context(moment))
            #expect(selection.count <= NowSelection.capacity, "(f) seed \(testCase.seed)")
            #expect(Set(selection.items.map(\.id)).count == selection.count, "(f) seed \(testCase.seed): no duplicates")
            #expect(selection.items.allSatisfy { ContextOracle.isValid($0, in: ContextOracle.Context(moment)) },
                    "(f) seed \(testCase.seed): every item is valid")
            #expect(selection.count == min(3, expected.valid), "(f) seed \(testCase.seed): min(3, valid)")
            #expect(selection.items == expected.items, "(f) seed \(testCase.seed): oracle order")
            selectionSizes[selection.count] += 1
        }
        let outcomeLog = RescheduleOutcome.allCases.map { "\($0) \(outcomes[$0, default: 0])" }.joined(separator: ", ")
        print("AC-M1-21: seeds \(SelectionCorpus.rescheduleSeeds), \(corpus.count) households, \(taskCount) tasks "
              + "(min \(minTasks), max \(maxTasks) per household), \(ended) with ended windows (\(endsAtNow) ending "
              + "exactly at now; \(restOverEnded) rest over, \(restingEnded) resting, \(completedEnded) completed)")
        print("AC-M1-21: outcomes \(outcomeLog); selection sizes 0/1/2/3 after the pass = "
              + selectionSizes.map(String.init).joined(separator: "/"))
        #expect(corpus.count >= 500)
        #expect(minTasks >= 50 && maxTasks <= 500)
        #expect(endsAtNow > 0 && restOverEnded > 0 && restingEnded > 0 && completedEnded > 0)
        #expect(RescheduleOutcome.allCases.allSatisfy { outcomes[$0, default: 0] > 0 })
    }

    // MARK: AC-M1-22 determinism

    @Test("AC-M1-22: identical inputs give identical selection and rescheduling outputs over 100 runs, and two RNG seeds give the same outputs")
    func determinism() throws {
        let corpus = try SelectionCorpus.reschedule.get()
        let cases = Array(corpus.prefix(10))
        var runs = 0
        for testCase in cases {
            let moment = testCase.moment
            func engine(perturbing rng: inout SplitMix64) -> (Household, NowSelection, NowSelection) {
                // M1's engine takes no RNG (no randomness in selection or rescheduling, brief Q7). The seeded RNG is
                // drawn from between runs so any hidden shared random state would show up as a difference.
                _ = rng.next()
                let after = Rescheduler.reschedule(testCase.household, at: moment.now, calendar: moment.calendar,
                                                   timeZone: moment.timeZone)
                return (after, NowSelector.select(from: testCase.household, in: moment),
                        NowSelector.select(from: after, in: moment))
            }
            var seedA = SplitMix64(seed: 1)
            var seedB = SplitMix64(seed: 0xDEAD_BEEF)
            let reference = engine(perturbing: &seedA)
            for run in 1...100 {
                let again = engine(perturbing: &seedA)
                #expect(again.0 == reference.0 && again.1 == reference.1 && again.2 == reference.2,
                        "seed \(testCase.seed), run \(run)")
                runs += 1
            }
            let other = engine(perturbing: &seedB)
            #expect(other.0 == reference.0 && other.1 == reference.1 && other.2 == reference.2,
                    "seed \(testCase.seed): a different RNG seed")
        }
        print("AC-M1-22: \(cases.count) households (seeds \(cases.first?.seed ?? 0)...\(cases.last?.seed ?? 0)), "
              + "\(runs) repeated runs of rescheduling and selection, plus RNG seeds 1 and 0xDEADBEEF: all identical")
    }
}
