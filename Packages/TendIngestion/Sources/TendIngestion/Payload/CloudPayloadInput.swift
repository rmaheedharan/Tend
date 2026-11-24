// The payload builder's input type and the context selector (brief Definitions "Cloud request"; ADR-0005 Decision 3;
// AC-M2-20; plan WI-M2-10). P-3, P-4.
//
// The builder's input can hold only three text values: the one capture, the room names and the shortlist titles. It has
// no field that could carry an ID, a date, a state, a member, audio, an image or a document, so media is refused by
// type (AC-M2-20 "Media"); a `Mirror` test lists its stored properties. The selector is the one place that reads the
// household for a request: a pure function of the capture, the household and the Q12 answer.
// Pure value types: no I/O, no clock, no logging.

import Foundation
import TendCore

/// Everything a cloud request may carry from the household and the capture (ADR-0005 Decision 3).
public struct CloudPayloadInput: Hashable, Sendable {
    /// The text of the single capture being processed, as given.
    public let capture: String
    /// The household's room names, as the user wrote them (Q19), in household order.
    public let roomNames: [String]
    /// Q12 = yes: the duplicate shortlist's titles for the capture, trimmed, in rank order (index n = position n), at
    /// most 10. Empty under Q12 = no.
    public let shortlistTitles: [String]

    /// The most titles a request may carry (Q12; the duplicate shortlist's limit). The builder refuses more (R28-F3).
    public static let maximumShortlistTitles = DuplicateShortlist.limit

    public init(capture: String, roomNames: [String], shortlistTitles: [String]) {
        self.capture = capture
        self.roomNames = roomNames
        self.shortlistTitles = shortlistTitles
    }

    /// The three values of a pipeline request (what a cloud adapter gives the builder, WI-M2-M6).
    public init(_ request: IngestionRequest) {
        self.init(capture: request.input, roomNames: request.roomNames, shortlistTitles: request.shortlistTitles)
    }
}

/// Derives the builder's input from the household (brief Definitions "Cloud request": "A pure, separate context
/// selector derives them from the household").
public enum CloudContextSelector {

    /// - The capture, unchanged.
    /// - Every room's name as written, in household order.
    /// - Under Q12 = yes, the duplicate shortlist for the capture text (`DuplicateShortlist`, brief Definitions steps
    ///   1–6): the trimmed titles in rank order, at most 10. This is the same shortlist the duplicate rules check index
    ///   claims against (`CloudTitleSharing.existingTaskCheck`). Under Q12 = no, no title.
    public static func input(capture: String, household: Household,
                             titleSharing: CloudTitleSharing) -> CloudPayloadInput {
        let titles: [String] = switch titleSharing {
        case .shortlistTitles: DuplicateShortlist.entries(for: capture, in: household).map(\.title)
        case .noTitles: []
        }
        return CloudPayloadInput(capture: capture, roomNames: household.rooms.map(\.name), shortlistTitles: titles)
    }
}
