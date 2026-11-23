// Server-sent-event framing for the cloud provider streams (plan WI-M2-12; AC-M2-24). FR-A1, P-3.
//
// The three providers stream `text/event-stream` bodies (OpenAI and Anthropic always; Gemini with `alt=sse`). The
// transport (WI-M2-14, WI-M2-M4) hands over byte chunks cut anywhere. This framer turns them into whole events by the
// WHATWG HTML "Server-sent events" parsing rules ("Interpreting an event stream"):
// - the stream is UTF-8, decoded with U+FFFD for invalid bytes; one leading BOM is dropped;
// - lines end with CRLF, LF or CR (a CR at the end of one chunk and an LF at the start of the next are one line end);
// - a line that starts with `:` is a comment; otherwise the field name runs to the first `:`, and one space after
//   that colon is removed from the value (a line with no colon is a field with an empty value);
// - `event` sets the type, `data` adds its value and an LF to the data buffer, `id` sets the last event ID unless the
//   value holds NUL, `retry` and unknown fields are ignored (there is no reconnection in this layer);
// - a blank line dispatches: with an empty data buffer nothing is dispatched; otherwise one trailing LF is removed and
//   the event (type `message` when none was set) is returned; the type and data are then cleared.
// An event that never got its blank line is not dispatched, and `finish()` reports the stream as `cutShort`.
//
// Pure value type: no I/O, no clock, no logging. Splitting happens on bytes (CR and LF never occur inside a UTF-8
// sequence), and each line is decoded whole, so a chunk cut inside a UTF-8 sequence gives the same text.

import Foundation

/// One dispatched server-sent event.
public struct ServerSentEvent: Hashable, Sendable {
    /// The `event` field, or `message` when the event had none.
    public var type: String
    /// The `data` lines joined with LF.
    public var data: String
    /// The last `id` seen in the stream so far (empty when none).
    public var lastEventID: String

    public init(type: String, data: String, lastEventID: String) {
        self.type = type
        self.data = data
        self.lastEventID = lastEventID
    }
}

/// How an event stream ended.
public enum ServerSentEventEnd: Hashable, Sendable {
    /// Every event was dispatched; nothing was left over.
    case complete
    /// The stream stopped inside a line or before an event's blank line; that event was not dispatched.
    case cutShort
}

/// Incremental `text/event-stream` framing over byte chunks.
public struct ServerSentEventFramer: Sendable {
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
    private static let colon: UInt8 = 0x3A
    private static let space: UInt8 = 0x20
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    private var line: [UInt8] = []
    private var lastWasCarriageReturn = false
    private var atStreamStart = true
    private var dataBuffer: [UInt8] = []
    private var eventType: [UInt8] = []
    private var lastEventID = ""
    private var closed = false

    public init() {}

    /// Reads the next chunk and returns the events it completes, in order. After `finish()` it returns nothing.
    public mutating func append(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent] {
        guard !closed else { return [] }
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if lastWasCarriageReturn {
                lastWasCarriageReturn = false
                if byte == Self.lineFeed { continue }
            }
            switch byte {
            case Self.lineFeed:
                processLine(into: &events)
            case Self.carriageReturn:
                processLine(into: &events)
                lastWasCarriageReturn = true
            default:
                line.append(byte)
            }
        }
        return events
    }

    /// Ends the stream. Anything not yet dispatched is dropped, as the event-stream rules say, and reported.
    public mutating func finish() -> ServerSentEventEnd {
        guard !closed else { return .complete }
        closed = true
        // A stream that holds only its BOM has no content left over (the BOM is dropped when the first line ends).
        let lineLeft = !line.isEmpty && !(atStreamStart && line == Self.byteOrderMark)
        let leftOver = lineLeft || !dataBuffer.isEmpty || !eventType.isEmpty
        line = []
        dataBuffer = []
        eventType = []
        return leftOver ? .cutShort : .complete
    }

    private mutating func processLine(into events: inout [ServerSentEvent]) {
        var bytes = line[...]
        line.removeAll(keepingCapacity: true)
        if atStreamStart {
            atStreamStart = false
            if bytes.starts(with: Self.byteOrderMark) { bytes = bytes.dropFirst(Self.byteOrderMark.count) }
        }
        guard let first = bytes.first else {
            dispatch(into: &events)
            return
        }
        if first == Self.colon { return }
        let name: ArraySlice<UInt8>
        var value: ArraySlice<UInt8>
        if let colonIndex = bytes.firstIndex(of: Self.colon) {
            name = bytes[..<colonIndex]
            value = bytes[bytes.index(after: colonIndex)...]
            if value.first == Self.space { value = value.dropFirst() }
        } else {
            name = bytes
            value = []
        }
        switch String(decoding: name, as: UTF8.self) {
        case "event":
            eventType = Array(value)
        case "data":
            dataBuffer.append(contentsOf: value)
            dataBuffer.append(Self.lineFeed)
        case "id":
            if !value.contains(0) { lastEventID = String(decoding: value, as: UTF8.self) }
        default:
            break  // `retry` and unknown fields: ignored.
        }
    }

    private mutating func dispatch(into events: inout [ServerSentEvent]) {
        defer {
            dataBuffer.removeAll(keepingCapacity: true)
            eventType.removeAll(keepingCapacity: true)
        }
        guard !dataBuffer.isEmpty else { return }
        if dataBuffer.last == Self.lineFeed { dataBuffer.removeLast() }
        let type = eventType.isEmpty ? "message" : String(decoding: eventType, as: UTF8.self)
        events.append(ServerSentEvent(type: type, data: String(decoding: dataBuffer, as: UTF8.self),
                                      lastEventID: lastEventID))
    }
}
