// Reading one provider event's JSON data (plan WI-M2-13; AC-M2-24). FR-A1.
//
// Every event payload is read one shot by `PartialJSONParser`, the same parser as the output text, so every JSON in
// the cloud path follows one set of rules on Linux and Darwin (dev-notes WI-M2-12, J8). The accessors below are
// strict about types: a member that is missing or `null` is "absent"; any other type than the expected one is
// `unexpectedStructure`, so a provider format change stops the stream calmly instead of being read wrongly.
// Pure: no I/O, no clock, no logging.

import Foundation

enum ProviderEventJSON {
    /// The event's data as a finished JSON object, or `eventNotJSON`.
    static func object(_ data: String) throws(ProviderStreamError) -> PartialJSONValue {
        var parser = PartialJSONParser()
        let value: PartialJSONValue
        do throws(PartialJSONError) {
            try parser.append(data.utf8)
            value = try parser.finish()
        } catch {
            throw .unreadable(.eventNotJSON)
        }
        guard case .object = value else { throw .unreadable(.eventNotJSON) }
        return value
    }
}

extension PartialJSONValue {
    /// The member for `key`, or nil when it is missing or `null`.
    func present(_ key: String) -> PartialJSONValue? {
        guard let value = self[key], value != .null else { return nil }
        return value
    }

    /// A string member; nil when missing or `null`.
    func string(_ key: String) throws(ProviderStreamError) -> String? {
        guard let value = present(key) else { return nil }
        guard case let .string(text, isComplete: true) = value else { throw .unreadable(.unexpectedStructure) }
        return text
    }

    /// A Boolean member; nil when missing or `null` (review R29-N1).
    func bool(_ key: String) throws(ProviderStreamError) -> Bool? {
        guard let value = present(key) else { return nil }
        guard case let .bool(flag) = value else { throw .unreadable(.unexpectedStructure) }
        return flag
    }

    /// An object member; nil when missing or `null`.
    func object(_ key: String) throws(ProviderStreamError) -> PartialJSONValue? {
        guard let value = present(key) else { return nil }
        guard case .object = value else { throw .unreadable(.unexpectedStructure) }
        return value
    }

    /// An array member's elements; nil when missing or `null`.
    func array(_ key: String) throws(ProviderStreamError) -> [PartialJSONValue]? {
        guard let value = present(key) else { return nil }
        guard case let .array(elements, isComplete: true) = value else { throw .unreadable(.unexpectedStructure) }
        return elements
    }

    /// A whole-number member; nil when missing or `null`. A non-number or a non-whole number is unexpected.
    func wholeNumber(_ key: String) throws(ProviderStreamError) -> Int? {
        guard let value = present(key) else { return nil }
        guard case let .number(text) = value, let number = ModelNumber.wholeNumber(jsonText: text) else {
            throw .unreadable(.unexpectedStructure)
        }
        return number
    }

    /// This value as an object, or `unexpectedStructure`.
    func requireObject() throws(ProviderStreamError) -> PartialJSONValue {
        guard case .object = self else { throw .unreadable(.unexpectedStructure) }
        return self
    }
}

/// What one event means: output text to read (possibly empty), then, optionally, a stop.
struct DialectStep: Sendable {
    var output = ""
    var stop: ProviderStreamError?
}
