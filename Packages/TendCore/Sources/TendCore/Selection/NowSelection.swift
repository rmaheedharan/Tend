import Foundation

/// At most three things that make sense to do right now (UX-2, FR-B1; AC-M1-13).
///
/// The cap is a property of the type, not of a view: a `NowSelection` has exactly three storage slots, so it cannot
/// hold a fourth item, and the only initialiser returns `nil` for more than `capacity` items or for the same task
/// twice. Its contents never change after creation. Later surfaces (Now canvas, widget, Live Activity) render it as
/// is; "more" is never a longer list (design.md). An empty selection is a normal, calm result, not an error (AC-M1-15).
public struct NowSelection: Hashable, Sendable {
    /// The most items a selection can ever hold (the Rule of Three).
    public static let capacity = 3

    /// A selection with nothing in it.
    public static let empty = NowSelection(first: nil, second: nil, third: nil)

    private let first: HouseholdTask?
    private let second: HouseholdTask?
    private let third: HouseholdTask?

    private init(first: HouseholdTask?, second: HouseholdTask?, third: HouseholdTask?) {
        self.first = first
        self.second = second
        self.third = third
    }

    /// A selection of `items`, in order. Returns `nil` if there are more than `capacity` items or if two items share
    /// a task ID.
    public init?(items: [HouseholdTask]) {
        guard items.count <= Self.capacity else { return nil }
        guard Set(items.map(\.id)).count == items.count else { return nil }
        self.init(
            first: items.count > 0 ? items[0] : nil,
            second: items.count > 1 ? items[1] : nil,
            third: items.count > 2 ? items[2] : nil
        )
    }

    /// The selected tasks, in ranked order (AC-M1-16). Never more than `capacity`.
    public var items: [HouseholdTask] {
        [first, second, third].compactMap { $0 }
    }

    public var count: Int {
        items.count
    }

    public var isEmpty: Bool {
        first == nil
    }
}
