import Foundation

// MARK: - Item

/// One row of a `DKSidebar`: a glyph, a label and, at the trailing edge, an
/// optional piece of meta text, a count, or a warning glyph.
///
/// `meta` wins over `count` when both are set. `metaTone` puts a small status
/// dot before the meta text ("● 1/4"). `isWarning` adds the warning glyph in the
/// warning color at the trailing edge; it never takes the accent.
public struct DKSidebarItem<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public var id: ID
    public var label: String
    public var glyph: DKGlyph
    public var meta: String?
    public var isMetaMonospaced: Bool
    public var metaTone: DKTone?
    public var isWarning: Bool
    public var count: Int?
    /// Read by VoiceOver after the label when the row shows the warning glyph.
    public var warningLabel: String
    /// A disabled row is dimmed, cannot be selected, and arrow keys skip it.
    public var isEnabled: Bool
    /// Why a disabled row is unavailable: its tooltip, and read by VoiceOver.
    public var disabledReason: String?

    public init(
        id: ID,
        label: String,
        glyph: DKGlyph,
        meta: String? = nil,
        isMetaMonospaced: Bool = false,
        metaTone: DKTone? = nil,
        isWarning: Bool = false,
        count: Int? = nil,
        warningLabel: String = "Needs attention",
        isEnabled: Bool = true,
        disabledReason: String? = nil,
    ) {
        self.id = id
        self.label = label
        self.glyph = glyph
        self.meta = meta
        self.isMetaMonospaced = isMetaMonospaced
        self.metaTone = metaTone
        self.isWarning = isWarning
        self.count = count
        self.warningLabel = warningLabel
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }

    /// The trailing text the row shows: the meta text, else the count, else nothing.
    /// Empty meta text counts as none.
    public var trailingText: String? {
        if let meta, !meta.isEmpty {
            return meta
        }
        return count.map(String.init)
    }

    /// What VoiceOver reads for the row: the label, the trailing text, and the
    /// warning when there is one.
    public var accessibilityText: String {
        [label, trailingText, isWarning ? warningLabel : nil, isEnabled ? nil : disabledReason]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Section

/// A group of sidebar rows under an optional small title ("Library", "Logs").
public struct DKSidebarSection<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var items: [DKSidebarItem<ID>]

    /// `id` defaults to the title, or for an untitled section to its item ids;
    /// pass one when two sections would otherwise share it.
    public init(_ title: String? = nil, id: String? = nil, items: [DKSidebarItem<ID>]) {
        self.id = id ?? title ?? items.map { "\($0.id)" }.joined(separator: "|")
        self.title = title
        self.items = items
    }
}

public extension Array {
    /// Every item of every section, top to bottom.
    func allSidebarItems<ID>() -> [DKSidebarItem<ID>] where Element == DKSidebarSection<ID> {
        flatMap(\.items)
    }

    /// The item `offset` enabled rows away from `id` across sections, for
    /// arrow-key navigation. Disabled rows are skipped. With no current item,
    /// moving down picks the first enabled row and moving up the last. Stops at
    /// the ends instead of wrapping.
    func sidebarItemID<ID>(from id: ID?, offset: Int) -> ID? where Element == DKSidebarSection<ID> {
        let items = allSidebarItems()
        let ids = items.filter(\.isEnabled).map(\.id)
        guard !ids.isEmpty else {
            return nil
        }
        guard let id, let current = items.firstIndex(where: { $0.id == id }) else {
            return offset >= 0 ? ids.first : ids.last
        }
        guard let index = ids.firstIndex(of: id) else {
            // The current row is disabled: step to the nearest enabled row in the direction of travel.
            let before = items[..<current].filter(\.isEnabled).map(\.id)
            let after = items[(current + 1)...].filter(\.isEnabled).map(\.id)
            if offset >= 0 {
                return after.isEmpty ? before.last : after[Swift.min(Swift.max(offset - 1, 0), after.count - 1)]
            }
            return before.isEmpty ? after.first : before[Swift.max(before.count + offset, 0)]
        }
        return ids[Swift.min(Swift.max(index + offset, 0), ids.count - 1)]
    }
}

// MARK: - Header and footer content

/// A key-value line under the machine name in a sidebar header ("iOS 26.6.2").
public struct DKSidebarFact: Identifiable, Hashable, Sendable {
    public var label: String
    public var value: String
    public var isMonospaced: Bool

    public var id: String {
        label
    }

    public init(_ label: String, _ value: String, isMonospaced: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
    }
}

/// A line of muted footer text, optionally led by a status dot
/// ("● Helper 2.6.0 ready") or set in monospace ("~/VPhone").
public struct DKSidebarFooterLine: Identifiable, Hashable, Sendable {
    public var text: String
    public var tone: DKTone?
    public var isMonospaced: Bool

    public var id: String {
        text
    }

    public init(_ text: String, tone: DKTone? = nil, isMonospaced: Bool = false) {
        self.text = text
        self.tone = tone
        self.isMonospaced = isMonospaced
    }
}
