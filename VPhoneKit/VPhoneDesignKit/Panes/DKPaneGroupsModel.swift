import Foundation
import Observation

// MARK: - Tab

/// One tab of a pane group. Its identity is `id`, whatever it carries: the
/// same document can have tabs in several groups.
///
/// `Payload` is unconstrained. The model never looks inside it; the caller
/// says how a tab looks (see `DKPaneGroupArea`'s `tab` closure).
///
/// Ported, with the rest of the pane groups, from uAppKit's `UPaneGroups`.
public struct DKPaneTab<Payload>: Identifiable {
    public let id: UUID
    public var payload: Payload
    /// A preview tab, in italics; a group holds at most one (see `openTab`).
    public var isTransient: Bool

    public init(id: UUID = UUID(), payload: Payload, isTransient: Bool = false) {
        self.id = id
        self.payload = payload
        self.isTransient = isTransient
    }
}

extension DKPaneTab: Equatable where Payload: Equatable {}
extension DKPaneTab: Sendable where Payload: Sendable {}

/// A leaf of the split tree: a strip of tabs and the one in front.
public struct DKPaneGroup<Payload>: Identifiable {
    public let id: UUID
    public var tabs: [DKPaneTab<Payload>]
    public var activeIndex: Int

    public init(id: UUID = UUID(), tabs: [DKPaneTab<Payload>] = [], activeIndex: Int = 0) {
        self.id = id
        self.tabs = tabs
        self.activeIndex = activeIndex
    }

    public var activeTab: DKPaneTab<Payload>? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }
}

extension DKPaneGroup: Equatable where Payload: Equatable {}
extension DKPaneGroup: Sendable where Payload: Sendable {}

/// A tab's standing in the whole area. With only "selected or not", several
/// strips each show a selected tab and nothing says which group has focus.
public enum DKPaneTabActivity: Sendable, Hashable {
    /// The front tab of the active group: one in the whole area.
    case active
    /// The front tab of a group that does not have focus.
    case frontUnfocused
    /// A tab behind another in its group.
    case inactive
}

// MARK: - Policy

public struct DKPaneGroupsPolicy: Sendable, Equatable {
    /// The most groups `splitGroup` makes; dragging a tab to an edge is not
    /// limited. Nil for no limit.
    public var splitMaxGroups: Int?
    /// Whether a group leaves the tree when its last tab closes.
    public var collapsesEmptyGroups: Bool
    /// Whether the last group may stay empty. The tree always keeps one group;
    /// when this is false, emptying the whole area calls `onAreaEmptied`, so
    /// the caller can close its window or add a tab.
    public var allowsLastGroupEmpty: Bool
    /// Which tabs stay mounted. Hidden tabs keep their view, so switching tabs
    /// is a change of opacity, not a rebuild.
    public var keepAlive: KeepAlive

    public enum KeepAlive: Sendable, Hashable {
        /// Every tab of every group.
        case allTabs
        /// The front tab of each group.
        case activeTabPerGroup
        /// The front tab of the active group.
        case activeGroupOnly
    }

    public init(
        splitMaxGroups: Int? = nil,
        collapsesEmptyGroups: Bool = true,
        allowsLastGroupEmpty: Bool = true,
        keepAlive: KeepAlive = .allTabs,
    ) {
        self.splitMaxGroups = splitMaxGroups
        self.collapsesEmptyGroups = collapsesEmptyGroups
        self.allowsLastGroupEmpty = allowsLastGroupEmpty
        self.keepAlive = keepAlive
    }
}

// MARK: - Model

/// Tab groups in a split tree, after VS Code's editor groups: each leaf of
/// `root` is a group with its own tabs and front tab, and one group in the
/// whole area is active. New tabs open in the active group, and commands go
/// to its front tab.
@MainActor
@Observable
public final class DKPaneGroupsModel<Payload> {
    /// The split tree; its leaves are group ids.
    public private(set) var root: DKPaneLayout
    public private(set) var groups: [UUID: DKPaneGroup<Payload>]
    /// Where new tabs open. A stale id falls back to the tree's first group.
    public var activeGroupID: UUID?
    public var policy: DKPaneGroupsPolicy

    // MARK: Hooks

    /// After a tab leaves the model, with every tab that remains.
    @ObservationIgnored public var onTabRemoved: ((_ removed: DKPaneTab<Payload>, _ remaining: [DKPaneTab<Payload>]) -> Void)?
    /// Copies a tab, for the only tab of a group dragged to that group's own
    /// edge: moving it would leave one group again. Nil refuses the split.
    @ObservationIgnored public var cloneTab: ((DKPaneTab<Payload>) -> DKPaneTab<Payload>?)?
    /// What `splitGroup` puts in the new group; nil leaves it empty.
    @ObservationIgnored public var makeTabForNewGroup: (() -> DKPaneTab<Payload>?)?
    /// The whole area emptied while `policy.allowsLastGroupEmpty` is false.
    @ObservationIgnored public var onAreaEmptied: (() -> Void)?

    public init(policy: DKPaneGroupsPolicy = .init()) {
        let group = DKPaneGroup<Payload>()
        groups = [group.id: group]
        root = .leaf(paneID: group.id)
        activeGroupID = group.id
        self.policy = policy
    }

    // MARK: Queries

    public var groupCount: Int {
        root.leafCount
    }

    /// Group ids, depth first.
    public var groupIDs: [UUID] {
        root.leafIDs
    }

    public var activeGroup: DKPaneGroup<Payload>? {
        if let id = activeGroupID, let group = groups[id] {
            return group
        }
        return root.firstLeafID.flatMap { groups[$0] }
    }

    public var activeTab: DKPaneTab<Payload>? {
        activeGroup?.activeTab
    }

    /// Every tab, group by group in tree order.
    public var allTabs: [DKPaneTab<Payload>] {
        root.leafIDs.flatMap { groups[$0]?.tabs ?? [] }
    }

    /// No tab anywhere, though empty groups may remain.
    public var isEmpty: Bool {
        root.leafIDs.allSatisfy { groups[$0]?.tabs.isEmpty ?? true }
    }

    public func tabActivity(groupID: UUID, index: Int) -> DKPaneTabActivity {
        guard groups[groupID]?.activeIndex == index else { return .inactive }
        return (activeGroupID ?? root.firstLeafID) == groupID ? .active : .frontUnfocused
    }

    public func locateTab(_ tabID: UUID) -> (groupID: UUID, index: Int)? {
        for groupID in root.leafIDs {
            if let index = groups[groupID]?.tabs.firstIndex(where: { $0.id == tabID }) {
                return (groupID, index)
            }
        }
        return nil
    }

    public func tab(_ tabID: UUID) -> DKPaneTab<Payload>? {
        guard let at = locateTab(tabID) else { return nil }
        return groups[at.groupID]?.tabs[at.index]
    }

    // MARK: Opening, Activating, Closing

    /// Opens a tab in the active group, or `groupID`, and makes it the front
    /// tab of the active group.
    ///
    /// A tab of that group that `dedupe` matches is brought forward instead.
    /// A transient tab replaces the group's transient tab. Returns the id of
    /// the tab in front afterwards.
    @discardableResult
    public func openTab(
        _ make: () -> DKPaneTab<Payload>,
        dedupe: ((DKPaneTab<Payload>) -> Bool)? = nil,
        asTransient: Bool = false,
        in groupID: UUID? = nil,
    ) -> UUID {
        let id = resolveGroupID(groupID)
        // Copy, change, write back: an optional-chained assignment from the
        // same dictionary is an exclusivity conflict.
        guard var group = groups[id] else {
            let tab = make()
            groups[id] = DKPaneGroup(id: id, tabs: [tab], activeIndex: 0)
            activeGroupID = id
            return tab.id
        }
        if let dedupe, let hit = group.tabs.firstIndex(where: dedupe) {
            group.activeIndex = hit
            if !asTransient, group.tabs[hit].isTransient {
                group.tabs[hit].isTransient = false
            }
            groups[id] = group
            activeGroupID = id
            return group.tabs[hit].id
        }
        var tab = make()
        tab.isTransient = asTransient
        if asTransient, let slot = group.tabs.firstIndex(where: \.isTransient) {
            group.tabs[slot] = tab
            group.activeIndex = slot
        } else {
            group.tabs.append(tab)
            group.activeIndex = group.tabs.count - 1
        }
        groups[id] = group
        activeGroupID = id
        return tab.id
    }

    public func activateTab(groupID: UUID, index: Int) {
        guard let group = groups[groupID], group.tabs.indices.contains(index) else { return }
        // Skip writes that change nothing: each one invalidates observers.
        if group.activeIndex != index {
            groups[groupID]?.activeIndex = index
        }
        if activeGroupID != groupID {
            activeGroupID = groupID
        }
    }

    public func promoteTransient(_ tabID: UUID) {
        guard let at = locateTab(tabID), groups[at.groupID]?.tabs[at.index].isTransient == true else { return }
        groups[at.groupID]?.tabs[at.index].isTransient = false
    }

    /// Closes a tab. A group that loses its last tab leaves the tree, unless
    /// it is the only group. This closes for real; the strip's close button
    /// only asks (`DKPaneGroupArea`'s `onRequestClose`).
    public func closeTab(groupID: UUID, index: Int) {
        guard var group = groups[groupID], group.tabs.indices.contains(index) else { return }
        let closed = group.tabs.remove(at: index)
        group.activeIndex = Self.adjustedActiveIndex(group.activeIndex, removedAt: index, newCount: group.tabs.count)
        groups[groupID] = group
        collapseIfEmpty(groupID)
        onTabRemoved?(closed, allTabs)
        if !policy.allowsLastGroupEmpty, isEmpty {
            onAreaEmptied?()
        }
    }

    public func closeTab(_ tabID: UUID) {
        guard let at = locateTab(tabID) else { return }
        closeTab(groupID: at.groupID, index: at.index)
    }

    /// Closes the active group's front tab, or the active group itself when it
    /// is an empty split. False when there was nothing to close.
    @discardableResult
    public func closeActiveTab() -> Bool {
        guard let group = activeGroup else { return false }
        guard group.activeTab != nil else { return closeEmptyGroup(groupID: group.id) }
        closeTab(groupID: group.id, index: group.activeIndex)
        return true
    }

    /// Removes an empty group from the tree; the only group stays.
    @discardableResult
    public func closeEmptyGroup(groupID: UUID) -> Bool {
        guard groups[groupID]?.tabs.isEmpty == true, !root.isSingleLeaf else { return false }
        collapseIfEmpty(groupID, force: true)
        return groups[groupID] == nil
    }

    /// Closes every tab `predicate` matches, one at a time: each close can
    /// shift indices and collapse a group.
    public func closeTabs(where predicate: (DKPaneTab<Payload>) -> Bool) {
        while true {
            var hit: (groupID: UUID, index: Int)?
            for groupID in root.leafIDs {
                if let index = groups[groupID]?.tabs.firstIndex(where: predicate) {
                    hit = (groupID, index)
                    break
                }
            }
            guard let hit else { return }
            closeTab(groupID: hit.groupID, index: hit.index)
        }
    }

    // MARK: Layout

    /// Splits `groupID`, putting what `makeTabForNewGroup` makes in the new
    /// group, within `policy.splitMaxGroups`.
    public func splitGroup(_ groupID: UUID, direction: DKSplitDirection = .horizontal, newLeafFirst: Bool = false) {
        if let cap = policy.splitMaxGroups, groupCount >= cap {
            return
        }
        guard groups[groupID] != nil else { return }
        var group = DKPaneGroup<Payload>()
        if let seed = makeTabForNewGroup?() {
            group.tabs = [seed]
        }
        groups[group.id] = group
        root = root.splitting(
            paneID: groupID, direction: direction, newPaneID: group.id,
            splitID: UUID(), newLeafFirst: newLeafFirst,
        )
        activeGroupID = group.id
    }

    public func focusGroup(_ groupID: UUID) {
        guard groups[groupID] != nil else { return }
        if activeGroupID != groupID {
            activeGroupID = groupID
        }
    }

    public func setFraction(_ fraction: Double, splitID: UUID) {
        root = root.settingFraction(fraction, splitID: splitID)
    }

    // MARK: Dragging

    /// Drops a tab on a group's zone: the center moves it into that group, an
    /// edge splits that group on that side with the tab in the new group. A
    /// source group left empty leaves the tree. The only tab of a group dropped
    /// on that group's own edge is copied through `cloneTab` instead.
    public func moveTab(_ tabID: UUID, toGroup targetID: UUID, zone: DKPaneDropZone) {
        guard groups[targetID] != nil, let source = locateTab(tabID) else { return }
        if zone == .center {
            guard source.groupID != targetID else { return }
            guard let tab = removeForMove(tabID, from: source), var target = groups[targetID] else { return }
            target.tabs.append(tab)
            target.activeIndex = target.tabs.count - 1
            groups[targetID] = target
            activeGroupID = targetID
            return
        }
        let direction: DKSplitDirection
        let newLeafFirst: Bool
        switch zone {
        case .leading: (direction, newLeafFirst) = (.horizontal, true)
        case .trailing: (direction, newLeafFirst) = (.horizontal, false)
        case .top: (direction, newLeafFirst) = (.vertical, true)
        case .bottom: (direction, newLeafFirst) = (.vertical, false)
        case .center: return
        }
        var group = DKPaneGroup<Payload>()
        if source.groupID == targetID, groups[source.groupID]?.tabs.count == 1 {
            guard let tab = groups[source.groupID]?.tabs.first, let clone = cloneTab?(tab) else { return }
            group.tabs = [clone]
        } else {
            guard let tab = removeForMove(tabID, from: source) else { return }
            group.tabs = [tab]
        }
        groups[group.id] = group
        root = root.splitting(
            paneID: targetID, direction: direction, newPaneID: group.id,
            splitID: UUID(), newLeafFirst: newLeafFirst,
        )
        activeGroupID = group.id
    }

    /// Puts a tab in the slot of another, in the same group or another one.
    public func reorderTab(_ tabID: UUID, before targetTabID: UUID) {
        guard tabID != targetTabID,
              let source = locateTab(tabID),
              let tab = groups[source.groupID]?.tabs[source.index],
              let target = locateTab(targetTabID)
        else { return }
        // Moving right within a group, the removal shifts the target left.
        var insertAt = target.index
        if source.groupID == target.groupID, source.index < target.index {
            insertAt -= 1
        }
        removeAdjustingActive(at: source)
        groups[target.groupID]?.tabs.insert(tab, at: insertAt)
        groups[target.groupID]?.activeIndex = insertAt
        activeGroupID = target.groupID
        if source.groupID != target.groupID {
            collapseIfEmpty(source.groupID)
        }
    }

    /// One empty group again, without `onTabRemoved`.
    public func reset() {
        let group = DKPaneGroup<Payload>()
        groups = [group.id: group]
        root = .leaf(paneID: group.id)
        activeGroupID = group.id
    }

    // MARK: Internals

    private func resolveGroupID(_ requested: UUID?) -> UUID {
        if let requested, groups[requested] != nil {
            return requested
        }
        if let id = activeGroupID, groups[id] != nil {
            return id
        }
        if let first = root.firstLeafID {
            return first
        }
        let group = DKPaneGroup<Payload>()
        groups[group.id] = group
        root = .leaf(paneID: group.id)
        activeGroupID = group.id
        return group.id
    }

    /// The front tab's index after the tab at `index` is removed.
    static func adjustedActiveIndex(_ current: Int, removedAt index: Int, newCount: Int) -> Int {
        var value = current
        if index < value {
            value -= 1
        } else if index == value {
            value = min(value, newCount - 1)
        }
        return max(0, value)
    }

    /// Takes a tab out for a move. A source left empty collapses first, so
    /// the target is still in the tree for the split that follows.
    private func removeForMove(_ tabID: UUID, from source: (groupID: UUID, index: Int)) -> DKPaneTab<Payload>? {
        guard let tab = groups[source.groupID]?.tabs[source.index], tab.id == tabID else { return nil }
        removeAdjustingActive(at: source)
        collapseIfEmpty(source.groupID)
        return tab
    }

    private func removeAdjustingActive(at source: (groupID: UUID, index: Int)) {
        guard var group = groups[source.groupID], group.tabs.indices.contains(source.index) else { return }
        group.tabs.remove(at: source.index)
        group.activeIndex = Self.adjustedActiveIndex(group.activeIndex, removedAt: source.index, newCount: group.tabs.count)
        groups[source.groupID] = group
    }

    private func collapseIfEmpty(_ groupID: UUID, force: Bool = false) {
        guard force || policy.collapsesEmptyGroups,
              groups[groupID]?.tabs.isEmpty == true, !root.isSingleLeaf,
              let newRoot = root.removingLeaf(paneID: groupID)
        else {
            fixActiveGroup()
            return
        }
        root = newRoot
        groups.removeValue(forKey: groupID)
        fixActiveGroup()
    }

    private func fixActiveGroup() {
        if activeGroupID.map({ groups[$0] == nil }) ?? true {
            activeGroupID = root.firstLeafID
        }
    }
}
