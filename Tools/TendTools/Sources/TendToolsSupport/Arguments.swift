// Hand-written argument parsing for the TendTools commands (no Swift Argument Parser: no new dependency, CLAUDE.md §6).
// Options are `--name value` or `--name=value`; flags are `--name`. Unknown options, repeats and missing values are
// usage errors.

import Foundation

public struct UsageError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public struct ParsedArguments: Equatable {
    public var options: [String: String]
    public var flags: Set<String>

    /// Parses `arguments` (without the program name) against the known option and flag names.
    public init(_ arguments: [String], options known: Set<String>, flags knownFlags: Set<String>) throws(UsageError) {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--"), argument.count > 2 else { throw UsageError("unexpected argument: \(argument)") }
            var name = String(argument.dropFirst(2))
            var value: String?
            if let equals = name.firstIndex(of: "=") {
                value = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            if knownFlags.contains(name) {
                guard value == nil else { throw UsageError("--\(name) takes no value") }
                guard flags.insert(name).inserted else { throw UsageError("--\(name) given twice") }
            } else if known.contains(name) {
                if value == nil {
                    index += 1
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw UsageError("--\(name) needs a value")
                    }
                    value = arguments[index]
                }
                guard options[name] == nil else { throw UsageError("--\(name) given twice") }
                options[name] = value
            } else {
                throw UsageError("unknown option: --\(name)")
            }
            index += 1
        }
        self.options = options
        self.flags = flags
    }

    public func required(_ name: String) throws(UsageError) -> String {
        guard let value = options[name], !value.isEmpty else { throw UsageError("--\(name) is required") }
        return value
    }
}

/// The file and output access a command needs, injected so the commands are testable without a real file system.
public struct ToolIO: Sendable {
    public var read: @Sendable (String) -> Data?
    public var write: @Sendable (String, Data) -> Bool
    public var standardOutput: @Sendable (String) -> Void
    public var standardError: @Sendable (String) -> Void

    public init(
        read: @escaping @Sendable (String) -> Data?, write: @escaping @Sendable (String, Data) -> Bool,
        standardOutput: @escaping @Sendable (String) -> Void, standardError: @escaping @Sendable (String) -> Void
    ) {
        self.read = read
        self.write = write
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// The real file system, standard output and standard error.
    public static let live = ToolIO(
        read: { FileManager.default.contents(atPath: $0) },
        write: { FileManager.default.createFile(atPath: $0, contents: $1) },
        standardOutput: { FileHandle.standardOutput.write(Data($0.utf8)) },
        standardError: { FileHandle.standardError.write(Data($0.utf8)) }
    )
}
