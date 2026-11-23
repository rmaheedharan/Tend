// The eval fixtures as the scorer reads them (AC-M2-14; brief "Eval scoring rules", "Fixtures"; plan layout
// `Fixtures/M2/eval/`: `inputs.json`, `household.json`, `golden.json`). FR-A1.
//
// The Acceptance Tester writes the content (AC-M2-14 "Authorship"; WI-M2-16). This file only fixes the format, so the
// scorer and the harness read the same thing. The format is in dev-notes WI-M2-15 ("Fixture formats"). Readers are
// strict about what they use (type, presence, known enum values, unique keys and IDs, keyword-folded match-group
// tokens) and ignore members they do not use, so the Tester may add notes or composition tags.

import Foundation
import TendCore

/// Why a fixture file cannot be used. Every case names the file and where.
public enum EvalFixtureError: Error, Sendable, Hashable {
    case notJSON(file: String, EvalJSONError)
    case unsupportedVersion(file: String)
    case missingMember(file: String, path: String)
    case wrongType(file: String, path: String, expected: String)
    case unknownValue(file: String, path: String, value: String)
    case keyRepeated(file: String, key: String)
    case idRepeated(file: String, id: String)
    case unknownReference(file: String, path: String, key: String)
    /// A match-group token is not one keyword (`Keywords.of(token) == [token]`), so it could never match.
    case tokenNotKeyword(file: String, path: String, token: String)
    case emptyMatchGroups(file: String, path: String)
    case invalidSeededTask(file: String, key: String, TaskInvariantViolation)
}

// MARK: - Model

public struct EvalFixtureInput: Sendable, Hashable {
    public var id: String
    public var mode: EvalInputMode
    /// The text handed to the pipeline (text) or the script read aloud (voice).
    public var text: String
}

public struct EvalSeededRoom: Sendable, Hashable {
    public var key: String
    public var id: UUID
    public var name: String
    public var lastTendedAt: EvalInstant?
}

public struct EvalSeededTask: Sendable, Hashable {
    public var key: String
    /// The M1 task (fixed UUID, T-29).
    public var task: HouseholdTask
    public var matchGroups: [Set<String>]

    public var isCompleted: Bool { task.state == .completed }
}

public struct EvalGoldenItem: Sendable, Hashable {
    public enum ExpectedRoom: Sendable, Hashable {
        case existing(roomKey: String)
        case new(name: String, alternates: [String])
        case none
    }

    public enum Expectation: Sendable, Hashable {
        case create
        case existing(seededKey: String)
    }

    public var inputID: String
    public var key: String
    public var matchGroups: [Set<String>]
    public var kind: TaskKind
    public var room: ExpectedRoom
    public var effort: Effort
    public var isCritical: Bool
    public var isDeepClean: Bool
    public var isWeatherDependent: Bool
    public var expect: Expectation
}

/// The three fixture files, read and cross-checked.
public struct EvalFixtures: Sendable, Hashable {
    public var inputs: [EvalFixtureInput]
    public var rooms: [EvalSeededRoom]
    public var tasks: [EvalSeededTask]
    /// In file order ("golden order", the segmentation tie-break).
    public var golden: [EvalGoldenItem]

    public static let fileVersion = 1

    public init(inputs: Data, household: Data, golden: Data) throws(EvalFixtureError) {
        let inputsRoot = try Self.parse(inputs, file: "inputs.json")
        let householdRoot = try Self.parse(household, file: "household.json")
        let goldenRoot = try Self.parse(golden, file: "golden.json")
        self.inputs = try Self.readInputs(inputsRoot)
        self.rooms = try Self.readRooms(householdRoot)
        self.tasks = try Self.readTasks(householdRoot, rooms: rooms)
        self.golden = try Self.readGolden(goldenRoot, inputs: self.inputs, rooms: rooms, tasks: tasks)
    }

    /// The 1-based position of an input in `inputs.json` (the `EvalIDGenerator` input number, plan "Eval harness ID
    /// generator").
    public func inputNumber(of inputID: String) -> Int? {
        inputs.firstIndex { $0.id == inputID }.map { $0 + 1 }
    }

    public func input(_ id: String) -> EvalFixtureInput? { inputs.first { $0.id == id } }

    /// A fresh copy of the seeded household (brief "Household state": every input starts from one).
    public var household: Household {
        Household(
            tasks: tasks.map(\.task),
            rooms: rooms.map { Room(id: $0.id, name: $0.name, lastTendedAt: $0.lastTendedAt?.date) }
        )
    }

    /// Room and task keys by fixture ID, for `DraftRecord(draft:roomKeys:taskKeys:)`.
    public var roomKeys: [UUID: String] { Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.key) }) }
    public var taskKeys: [UUID: String] { Dictionary(uniqueKeysWithValues: tasks.map { ($0.task.id, $0.key) }) }

    // MARK: - Reading

    static func parse(_ data: Data, file: String) throws(EvalFixtureError) -> EvalJSON {
        let root: EvalJSON
        do throws(EvalJSONError) { root = try EvalJSONReader.parse(data) } catch { throw .notJSON(file: file, error) }
        guard root["schemaVersion"] == .integer(fileVersion) else { throw .unsupportedVersion(file: file) }
        return root
    }

    static func readInputs(_ root: EvalJSON) throws(EvalFixtureError) -> [EvalFixtureInput] {
        let r = FixtureReader(file: "inputs.json")
        var seen: Set<String> = []
        var result: [EvalFixtureInput] = []
        for (index, item) in try r.array(root, "inputs", at: "").enumerated() {
            let path = "/inputs/\(index)"
            let id = try r.string(item, "id", at: path)
            guard seen.insert(id).inserted else { throw .keyRepeated(file: r.file, key: id) }
            result.append(EvalFixtureInput(
                id: id, mode: try r.enumValue(item, "mode", at: path), text: try r.string(item, "text", at: path)
            ))
        }
        return result
    }

    static func readRooms(_ root: EvalJSON) throws(EvalFixtureError) -> [EvalSeededRoom] {
        let r = FixtureReader(file: "household.json")
        var keys: Set<String> = []
        var ids: Set<UUID> = []
        var result: [EvalSeededRoom] = []
        for (index, item) in try r.array(root, "rooms", at: "").enumerated() {
            let path = "/rooms/\(index)"
            let key = try r.string(item, "key", at: path)
            let id = try r.uuid(item, "id", at: path)
            guard keys.insert(key).inserted else { throw .keyRepeated(file: r.file, key: key) }
            guard ids.insert(id).inserted else { throw .idRepeated(file: r.file, id: id.uuidString) }
            result.append(EvalSeededRoom(
                key: key, id: id, name: try r.string(item, "name", at: path),
                lastTendedAt: try r.optionalInstant(item, "lastTendedAt", at: path)
            ))
        }
        return result
    }

    static func readTasks(_ root: EvalJSON, rooms: [EvalSeededRoom]) throws(EvalFixtureError) -> [EvalSeededTask] {
        let r = FixtureReader(file: "household.json")
        var keys: Set<String> = []
        var ids: Set<UUID> = Set(rooms.map(\.id))
        var result: [EvalSeededTask] = []
        for (index, item) in try r.array(root, "tasks", at: "").enumerated() {
            let path = "/tasks/\(index)"
            let key = try r.string(item, "key", at: path)
            let id = try r.uuid(item, "id", at: path)
            guard keys.insert(key).inserted else { throw .keyRepeated(file: r.file, key: key) }
            guard ids.insert(id).inserted else { throw .idRepeated(file: r.file, id: id.uuidString) }
            var roomID: UUID?
            if let roomKey = try r.optionalString(item, "roomKey", at: path) {
                guard let room = rooms.first(where: { $0.key == roomKey }) else {
                    throw .unknownReference(file: r.file, path: path + "/roomKey", key: roomKey)
                }
                roomID = room.id
            }
            let stateName = try r.string(item, "state", at: path)
            let state: TaskState
            switch stateName {
            case "active": state = .active
            case "maintenance": state = .maintenance
            case "resurfaced": state = .resurfaced
            case "completed": state = .completed
            case "deferred": state = .deferred(until: try r.instant(item, "deferredUntil", at: path).date)
            default: throw .unknownValue(file: r.file, path: path + "/state", value: stateName)
            }
            let title = try r.string(item, "title", at: path)
            let kind: TaskKind = try r.enumValue(item, "kind", at: path)
            let effort: Effort = try r.enumValue(item, "effort", at: path)
            let isCritical = try r.bool(item, "isCritical", at: path)
            let isDeepClean = try r.bool(item, "isDeepClean", at: path)
            let isWeatherDependent = try r.bool(item, "isWeatherDependent", at: path)
            let dayparts: [Daypart] = try r.enumArray(item, "allowedDayparts", at: path)
            let weekdays: [Weekday] = try r.enumArray(item, "allowedWeekdays", at: path)
            let windowStart = try r.instant(item, "windowStart", at: path).date
            let windowEnd = try r.instant(item, "windowEnd", at: path).date
            let interval = try r.optionalInteger(item, "recurrenceIntervalDays", at: path)
            let completedAt = try r.optionalInstant(item, "completedAt", at: path)?.date
            let task: HouseholdTask
            do throws(TaskInvariantViolation) {
                task = try HouseholdTask(
                    id: id, title: title, kind: kind, roomID: roomID, effort: effort, isCritical: isCritical,
                    isDeepClean: isDeepClean, isWeatherDependent: isWeatherDependent,
                    allowedDayparts: Set(dayparts), allowedWeekdays: Set(weekdays), windowStart: windowStart,
                    windowEnd: windowEnd, recurrenceIntervalDays: interval, state: state, completedAt: completedAt
                )
            } catch {
                throw .invalidSeededTask(file: r.file, key: key, error)
            }
            result.append(EvalSeededTask(key: key, task: task, matchGroups: try r.matchGroups(item, at: path)))
        }
        return result
    }

    static func readGolden(
        _ root: EvalJSON, inputs: [EvalFixtureInput], rooms: [EvalSeededRoom], tasks: [EvalSeededTask]
    ) throws(EvalFixtureError) -> [EvalGoldenItem] {
        let r = FixtureReader(file: "golden.json")
        // Golden and seeded keys share one namespace, so every log line names one thing.
        var keys: Set<String> = Set(tasks.map(\.key))
        var result: [EvalGoldenItem] = []
        for (index, item) in try r.array(root, "items", at: "").enumerated() {
            let path = "/items/\(index)"
            let inputID = try r.string(item, "inputID", at: path)
            guard inputs.contains(where: { $0.id == inputID }) else {
                throw .unknownReference(file: r.file, path: path + "/inputID", key: inputID)
            }
            let key = try r.string(item, "key", at: path)
            guard keys.insert(key).inserted else { throw .keyRepeated(file: r.file, key: key) }
            guard let roomJSON = item["room"] else { throw .missingMember(file: r.file, path: path + "/room") }
            let roomType = try r.string(roomJSON, "type", at: path + "/room")
            let room: EvalGoldenItem.ExpectedRoom
            switch roomType {
            case "existing":
                let roomKey = try r.string(roomJSON, "roomKey", at: path + "/room")
                guard rooms.contains(where: { $0.key == roomKey }) else {
                    throw .unknownReference(file: r.file, path: path + "/room/roomKey", key: roomKey)
                }
                room = .existing(roomKey: roomKey)
            case "new":
                room = .new(
                    name: try r.string(roomJSON, "name", at: path + "/room"),
                    alternates: try r.stringArray(roomJSON, "alternates", at: path + "/room")
                )
            case "none": room = .none
            default: throw .unknownValue(file: r.file, path: path + "/room/type", value: roomType)
            }
            guard let expectJSON = item["expect"] else { throw .missingMember(file: r.file, path: path + "/expect") }
            let expectType = try r.string(expectJSON, "type", at: path + "/expect")
            let expect: EvalGoldenItem.Expectation
            switch expectType {
            case "create": expect = .create
            case "existing":
                let seededKey = try r.string(expectJSON, "seededKey", at: path + "/expect")
                guard tasks.contains(where: { $0.key == seededKey }) else {
                    throw .unknownReference(file: r.file, path: path + "/expect/seededKey", key: seededKey)
                }
                expect = .existing(seededKey: seededKey)
            default: throw .unknownValue(file: r.file, path: path + "/expect/type", value: expectType)
            }
            result.append(EvalGoldenItem(
                inputID: inputID, key: key, matchGroups: try r.matchGroups(item, at: path),
                kind: try r.enumValue(item, "kind", at: path), room: room,
                effort: try r.enumValue(item, "effort", at: path), isCritical: try r.bool(item, "isCritical", at: path),
                isDeepClean: try r.bool(item, "isDeepClean", at: path),
                isWeatherDependent: try r.bool(item, "isWeatherDependent", at: path), expect: expect
            ))
        }
        return result
    }
}

/// Typed member access for one fixture file.
struct FixtureReader {
    let file: String

    func member(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> EvalJSON {
        guard case .object = object else { throw .wrongType(file: file, path: path, expected: "object") }
        guard let value = object[name] else { throw .missingMember(file: file, path: path + "/" + name) }
        return value
    }

    func string(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> String {
        guard case let .string(text) = try member(object, name, at: path) else {
            throw .wrongType(file: file, path: path + "/" + name, expected: "string")
        }
        return text
    }

    func optionalString(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> String? {
        switch object[name] {
        case nil, .null?: return nil
        case let .string(text)?: return text
        default: throw .wrongType(file: file, path: path + "/" + name, expected: "string or null")
        }
    }

    func bool(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> Bool {
        guard case let .bool(value) = try member(object, name, at: path) else {
            throw .wrongType(file: file, path: path + "/" + name, expected: "boolean")
        }
        return value
    }

    func optionalInteger(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> Int? {
        switch object[name] {
        case nil, .null?: return nil
        case let .integer(value)?: return value
        default: throw .wrongType(file: file, path: path + "/" + name, expected: "integer or null")
        }
    }

    func array(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> [EvalJSON] {
        guard case let .array(values) = try member(object, name, at: path) else {
            throw .wrongType(file: file, path: path + "/" + name, expected: "array")
        }
        return values
    }

    func stringArray(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> [String] {
        var result: [String] = []
        for (index, value) in try array(object, name, at: path).enumerated() {
            guard case let .string(text) = value else {
                throw .wrongType(file: file, path: path + "/\(name)/\(index)", expected: "string")
            }
            result.append(text)
        }
        return result
    }

    func enumValue<E: RawRepresentable>(
        _ object: EvalJSON, _ name: String, at path: String
    ) throws(EvalFixtureError) -> E where E.RawValue == String {
        let text = try string(object, name, at: path)
        guard let value = E(rawValue: text) else { throw .unknownValue(file: file, path: path + "/" + name, value: text) }
        return value
    }

    func enumArray<E: RawRepresentable>(
        _ object: EvalJSON, _ name: String, at path: String
    ) throws(EvalFixtureError) -> [E] where E.RawValue == String {
        var result: [E] = []
        for (index, text) in try stringArray(object, name, at: path).enumerated() {
            guard let value = E(rawValue: text) else {
                throw .unknownValue(file: file, path: path + "/\(name)/\(index)", value: text)
            }
            result.append(value)
        }
        return result
    }

    func uuid(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> UUID {
        let text = try string(object, name, at: path)
        guard let id = UUID(uuidString: text) else { throw .unknownValue(file: file, path: path + "/" + name, value: text) }
        return id
    }

    func instant(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> EvalInstant {
        let text = try string(object, name, at: path)
        guard let instant = EvalInstant(text: text) else {
            throw .unknownValue(file: file, path: path + "/" + name, value: text)
        }
        return instant
    }

    func optionalInstant(_ object: EvalJSON, _ name: String, at path: String) throws(EvalFixtureError) -> EvalInstant? {
        guard let text = try optionalString(object, name, at: path) else { return nil }
        guard let instant = EvalInstant(text: text) else {
            throw .unknownValue(file: file, path: path + "/" + name, value: text)
        }
        return instant
    }

    /// Match groups: a non-empty array of non-empty arrays of tokens, each already one keyword (brief "Fixtures":
    /// "a set of synonym tokens, already keyword-folded").
    func matchGroups(_ object: EvalJSON, at path: String) throws(EvalFixtureError) -> [Set<String>] {
        let groups = try array(object, "matchGroups", at: path)
        guard !groups.isEmpty else { throw .emptyMatchGroups(file: file, path: path + "/matchGroups") }
        var result: [Set<String>] = []
        for (index, group) in groups.enumerated() {
            let groupPath = path + "/matchGroups/\(index)"
            guard case let .array(tokens) = group else { throw .wrongType(file: file, path: groupPath, expected: "array") }
            guard !tokens.isEmpty else { throw .emptyMatchGroups(file: file, path: groupPath) }
            var set: Set<String> = []
            for token in tokens {
                guard case let .string(text) = token else {
                    throw .wrongType(file: file, path: groupPath, expected: "string")
                }
                guard Keywords.of(text) == [text] else { throw .tokenNotKeyword(file: file, path: groupPath, token: text) }
                set.insert(text)
            }
            result.append(set)
        }
        return result
    }
}
