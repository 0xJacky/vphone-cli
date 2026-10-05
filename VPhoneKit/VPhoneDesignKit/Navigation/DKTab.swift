import Foundation

// MARK: - Tab

/// One tab of a `DKTabStrip`.
///
/// A tab leads with a status dot (`statusTone`, for terminal sessions) or a
/// glyph, or both. `isTransient` marks a preview tab: its title is italic and
/// opening another preview replaces it (see `openTab(_:)`). `isDirty` shows the
/// accent unsaved dot. A tab that is not `isClosable` has no close button and
/// `closeTab(_:selection:)` leaves it alone.
public struct DKTab<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public var id: ID
    public var title: String
    public var glyph: DKGlyph?
    public var statusTone: DKTone?
    public var isClosable: Bool
    public var isTransient: Bool
    public var isDirty: Bool
    /// The tooltip; a full path when the title is a file name.
    public var help: String?

    public init(
        id: ID,
        title: String,
        glyph: DKGlyph? = nil,
        statusTone: DKTone? = nil,
        isClosable: Bool = true,
        isTransient: Bool = false,
        isDirty: Bool = false,
        help: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.glyph = glyph
        self.statusTone = statusTone
        self.isClosable = isClosable
        self.isTransient = isTransient
        self.isDirty = isDirty
        self.help = help
    }
}

// MARK: - Tab list operations

public extension Array {
    /// The selection after the tab `id` closes. Closing the selected tab
    /// selects its right neighbor, or its left one when it was last, or nothing
    /// when it was alone. Closing any other tab keeps the selection. A tab that
    /// is not closable, or not in the list, changes nothing.
    func selectionAfterClosingTab<ID>(_ id: ID, selection: ID?) -> ID? where Element == DKTab<ID> {
        guard let index = firstIndex(where: { $0.id == id }), self[index].isClosable, id == selection else {
            return selection
        }
        if index + 1 < count {
            return self[index + 1].id
        }
        return index > 0 ? self[index - 1].id : nil
    }

    /// Removes the closable tab `id` and returns the selection that follows
    /// (see `selectionAfterClosingTab(_:selection:)`).
    @discardableResult
    mutating func closeTab<ID>(_ id: ID, selection: ID?) -> ID? where Element == DKTab<ID> {
        let next = selectionAfterClosingTab(id, selection: selection)
        if let index = firstIndex(where: { $0.id == id }), self[index].isClosable {
            remove(at: index)
        }
        return next
    }

    /// Adds `tab` and returns the id to select.
    ///
    /// A tab already in the list is reused; opening it as a permanent tab
    /// keeps a transient one. A transient tab takes the place of the current
    /// transient tab, if there is one, so there is at most one preview.
    /// Otherwise the tab is appended.
    @discardableResult
    mutating func openTab<ID>(_ tab: DKTab<ID>) -> ID where Element == DKTab<ID> {
        if let index = firstIndex(where: { $0.id == tab.id }) {
            if !tab.isTransient {
                self[index].isTransient = false
            }
        } else if tab.isTransient, let index = firstIndex(where: \.isTransient) {
            self[index] = tab
        } else {
            append(tab)
        }
        return tab.id
    }

    /// Turns the transient tab `id` into a permanent one, as double-clicking
    /// a preview tab does.
    mutating func keepTab<ID>(_ id: ID) where Element == DKTab<ID> {
        if let index = firstIndex(where: { $0.id == id }) {
            self[index].isTransient = false
        }
    }
}
