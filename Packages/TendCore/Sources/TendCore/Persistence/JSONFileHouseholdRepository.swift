import Foundation

/// A `HouseholdRepository` that keeps the household in one local JSON file (AC-M1-04…07, AC-M1-25, P-2, ADR-0004).
///
/// Foundation only, so it runs on Linux and on device. The file lives at a caller-supplied local URL; nothing leaves
/// the device. All of `TendCore`'s file access is in this one source file.
///
/// - **Format (ADR-0004):** the `Household` encoded with `JSONEncoder`, keys sorted, dates written as seconds since the
///   reference date (a JSON number that reads back bit-exact, R-7). The top-level `schemaVersion` is read first, so a
///   file from another version is reported as `unsupportedSchemaVersion` even if the rest of its shape differs.
/// - **Load:** no file yet means nothing was saved, and gives an empty household. A file that exists but cannot be read
///   throws a typed `HouseholdStoreError`; the file is never modified by a load (AC-M1-06).
/// - **Save:** the whole household is encoded first, then handed to the write primitive, which replaces the file
///   atomically or not at all (AC-M1-07). The standard primitive is Foundation's `.atomic` write: a staging file in
///   the same directory, renamed over the old one. `FileManager.replaceItemAt` is deliberately not used: on Linux
///   (Swift 6.2.4) it can remove the existing file and then fail (R-8, ADR-0004).
/// - **Edits** (`upsertTask`, `removeTask`, `updateRoom`) read, edit and save inside the actor, so concurrent calls on
///   one instance never lose an update. They throw, and write nothing, if the stored file cannot be read.
///
/// Two instances on the same file are not coordinated with each other: the last save wins whole, never torn.
public actor JSONFileHouseholdRepository: HouseholdRepository {
    public nonisolated let fileURL: URL
    private let writer: HouseholdFileWriter

    /// A repository on the local file at `fileURL`. The directory must exist; the file is created on first save.
    public init(fileURL: URL) {
        self.init(fileURL: fileURL, writer: .standard)
    }

    /// The fault-injection seam (AC-M1-07): tests pass a writer that fails part-way.
    init(fileURL: URL, writer: HouseholdFileWriter) {
        self.fileURL = fileURL
        self.writer = writer
    }

    public func load() throws(HouseholdStoreError) -> Household {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return .empty
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .unreadableFile
        }
        return try Self.decode(data)
    }

    public func save(_ household: Household) throws(HouseholdStoreError) {
        try household.checkSchemaVersionIsCurrent()
        let data = try Self.encodeForSaving(household)
        do {
            try writer.write(data, fileURL)
        } catch {
            throw .writeUnsuccessful
        }
    }

    public func upsertTask(_ task: HouseholdTask) throws(HouseholdStoreError) {
        var household = try load()
        household.upsertTask(task)
        try save(household)
    }

    public func removeTask(id: HouseholdTask.ID) throws(HouseholdStoreError) {
        var household = try load()
        household.removeTask(id: id)
        try save(household)
    }

    public func updateRoom(_ room: Room) throws(HouseholdStoreError) {
        var household = try load()
        household.updateRoom(room)
        try save(household)
    }
}

// MARK: - File format (ADR-0004)

extension JSONFileHouseholdRepository {
    /// Only the version, read before anything else.
    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
    }

    /// The exact bytes this repository writes for `household`.
    static func encode(_ household: Household) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Seconds since 2001-01-01 as a JSON number. Swift writes the shortest digits that read back to the same
        // `Double`, so dates are bit-exact (R-7). ISO-8601 would drop everything below a second.
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(household)
    }

    private static func encodeForSaving(_ household: Household) throws(HouseholdStoreError) -> Data {
        do {
            return try encode(household)
        } catch {
            throw .writeUnsuccessful  // for example a non-finite date, which JSON cannot hold
        }
    }

    static func decode(_ data: Data) throws(HouseholdStoreError) -> Household {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate

        let probe: SchemaVersionProbe
        do {
            probe = try decoder.decode(SchemaVersionProbe.self, from: data)
        } catch {
            throw .unreadableFile
        }
        guard probe.schemaVersion == Household.currentSchemaVersion else {
            throw .unsupportedSchemaVersion(probe.schemaVersion)
        }

        do {
            return try decoder.decode(Household.self, from: data)
        } catch let violation as TaskInvariantViolation {
            throw .invalidTask(violation)
        } catch {
            throw .unreadableFile
        }
    }
}

// MARK: - Write seam (AC-M1-07)

/// Writes the encoded household to its file. The contract: replace the file **atomically or not at all**; never leave
/// it partly written, empty or removed. Internal, so only tests can swap it (fault injection).
struct HouseholdFileWriter: Sendable {
    var write: @Sendable (_ data: Data, _ destination: URL) throws -> Void

    init(write: @escaping @Sendable (_ data: Data, _ destination: URL) throws -> Void) {
        self.write = write
    }

    /// Foundation's atomic write: a staging file in the same directory, then a rename over the destination.
    static let standard = HouseholdFileWriter { data, destination in
        try data.write(to: destination, options: .atomic)
    }
}
