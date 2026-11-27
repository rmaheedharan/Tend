// The cloud request: the builder's plain value (brief Definitions "Cloud request": method, host, path, header names
// and body bytes; ADR-0005 Decision 3; AC-M2-20). P-3, P-4.
//
// The transport (`TendAI`, WI-M2-M4, behind WI-M2-14's neutral `CloudTransport`) turns it into a `URLRequest`. The key
// sits only in the auth header, as an `APIKey`, and is read only through `withValue`. A request's `description`,
// `debugDescription` and reflection show the provider, method, host, path, query, header names and the body's byte
// count, never a header value of the auth header and never the body, so neither the key nor the capture can reach a
// log or an error message by formatting (AC-M2-21, P-4).
// Pure values: no I/O, no clock, no logging.

import Foundation

/// One query item (name and value), in order.
public struct CloudQueryItem: Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// One request header. The auth header's value holds the key and is never shown.
public struct CloudRequestHeader: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    enum Content: Equatable, Sendable {
        case text(String)
        case key(prefix: String, APIKey)
    }

    public let name: String
    let content: Content

    init(name: String, content: Content) {
        self.name = name
        self.content = content
    }

    /// Whether this header carries the API key.
    public var isAuthorization: Bool {
        if case .key = content { return true }
        return false
    }

    /// False only for an auth header whose key holds a character outside U+0021…U+007E, or is empty: the transport
    /// refuses such a request before sending (PO R28-F5; AC-M2-23 `requestNotSent`).
    public var keyIsSendable: Bool {
        switch content {
        case .text: true
        case let .key(_, key): APIKeyText.isSendable(key)
        }
    }

    /// Gives the header's value to `body` only (the transport sets it; tests compare it).
    public func withValue<Result>(_ body: (String) throws -> Result) rethrows -> Result {
        switch content {
        case let .text(value): try body(value)
        case let .key(prefix, key): try key.withSecret { try body(prefix + $0) }
        }
    }

    public var description: String {
        switch content {
        case let .text(value): name + ": " + value
        case .key: name + ": (hidden)"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["name": name], displayStyle: .struct) }
}

/// One cloud request for one capture (the builder's output).
public struct CloudRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public let provider: CloudProvider
    public let model: CloudModel
    /// Always `POST`.
    public let method: String
    /// The bare host from the provider table.
    public let host: String
    public let path: String
    public let queryItems: [CloudQueryItem]
    /// In order: the auth header first, then the provider's fixed headers, then `User-Agent: Tend` and
    /// `Accept-Language: en-US` (PO WI-M2-10 ruling 4, GR-3). Transport-set headers (`Content-Length`, `Host`,
    /// `Accept`, `Accept-Encoding`, `Connection`) are not here; the allowed key-path lists name them as derived.
    public let headers: [CloudRequestHeader]
    /// The canonical JSON body.
    public let body: Data

    public var headerNames: [String] { headers.map(\.name) }

    public var description: String {
        var target = host + path
        if !queryItems.isEmpty { target += "?" + queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&") }
        return "CloudRequest(\(provider) \(model.rawValue) \(method) \(target), headers: "
            + headerNames.joined(separator: ", ") + ", body: \(body.count) bytes)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["provider": provider, "model": model, "method": method, "host": host, "path": path,
                                "queryItems": queryItems, "headerNames": headerNames, "bodyByteCount": body.count],
               displayStyle: .struct)
    }
}
