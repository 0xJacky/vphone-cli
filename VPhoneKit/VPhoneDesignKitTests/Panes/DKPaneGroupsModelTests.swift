import Foundation
import Testing
@testable import VPhoneDesignKit

/// A payload shaped like a real app's: an enum with associated values, one
/// pointing at a backing document. Ported from uAppKit's UPaneGroupsTests.
enum DKTestPayload: Equatable, Sendable {
    case table(String, doc: UUID)
    case scratch
}

@MainActor
private func makeModel(_ policy: DKPaneGroupsPolicy = .init()) -> DKPaneGroupsModel<DKTestPayload> {
    DKPaneGroupsModel(policy: policy)
}

private func tab(_ name: String, doc: UUID = UUID()) -> DKPaneTab<DKTestPayload> {
    DKPaneTab(payload: .table(name, doc: doc))
}

private func named(_ name: String) -> (DKPaneTab<DKTestPayload>) -> Bool {
    { tab in
        if case let .table(value, _) = tab.payload {
            return value == name
        }
        return false
    }
}

private final class Calls<Value>: @unchecked Sendable {
    var values: [Value] = []
}

// MARK: - Opening

@MainActor
@Suite("Pane groups: opening")
struct DKPaneGroupsOpenTests {
    @Test
    func `a new model has one empty active group`() {
        let model = makeModel()
        #expect(model.groupCount == 1)
        #expect(model.groups.count == 1)
        #expect(model.activeGroupID == model.root.firstLeafID)
        #expect(model.isEmpty)
        #expect(model.activeTab == nil)
    }

    @Test
    func `opening appends and activates`() {
        let model = makeModel()
        let a = model.openTab { tab("users") }
        let b = model.openTab { tab("orders") }
        #expect(a != b)
        #expect(model.activeGroup?.tabs.count == 2)
        #expect(model.activeTab?.id == b)
        #expect(model.allTabs.count == 2)
    }

    @Test
    func `a duplicate brings the existing tab forward with its document`() {
        let model = makeModel()
        let doc = UUID()
        let first = model.openTab { tab("users", doc: doc) }
        model.openTab { tab("orders") }
        let again = model.openTab({ tab("users") }, dedupe: named("users"))
        #expect(again == first)
        #expect(model.activeGroup?.tabs.count == 2)
        #expect(model.activeTab?.payload == .table("users", doc: doc))
    }

    @Test
    func `duplicates are looked for in the target group only`() throws {
        let model = makeModel()
        let doc1 = UUID()
        model.openTab { tab("users", doc: doc1) }
        let source = try #require(model.activeGroupID)
        model.splitGroup(source)
        let second = try #require(model.activeGroupID)
        #expect(source != second)

        let doc2 = UUID()
        let opened = model.openTab({ tab("users", doc: doc2) }, dedupe: named("users"))
        #expect(model.groups[second]?.tabs.map(\.id) == [opened])
        #expect(model.groups[second]?.tabs.first?.payload == .table("users", doc: doc2))
        #expect(model.groups[source]?.tabs.first?.payload == .table("users", doc: doc1))
    }

    @Test
    func `a preview tab replaces the group's preview tab`() {
        let model = makeModel()
        model.openTab { tab("pinned") }
        let first = model.openTab({ tab("a") }, asTransient: true)
        let second = model.openTab({ tab("b") }, asTransient: true)
        #expect(model.activeGroup?.tabs.count == 2)
        #expect(model.activeGroup?.tabs.filter(\.isTransient).count == 1)
        #expect(model.activeTab?.id == second)
        #expect(model.tab(first) == nil)
    }

    @Test
    func `keeping a preview tab stops the next preview from replacing it`() {
        let model = makeModel()
        let preview = model.openTab({ tab("a") }, asTransient: true)
        model.promoteTransient(preview)
        #expect(model.tab(preview)?.isTransient == false)
        model.openTab({ tab("b") }, asTransient: true)
        #expect(model.activeGroup?.tabs.count == 2)
    }

    @Test
    func `opening a preview tab for real keeps it`() {
        let model = makeModel()
        let preview = model.openTab({ tab("a") }, asTransient: true)
        let again = model.openTab({ tab("a") }, dedupe: named("a"))
        #expect(again == preview)
        #expect(model.tab(preview)?.isTransient == false)
    }

    @Test
    func `opening in a given group focuses that group`() throws {
        let model = makeModel()
        let first = try #require(model.activeGroupID)
        model.splitGroup(first)
        let second = try #require(model.activeGroupID)
        model.openTab({ tab("x") }, in: first)
        #expect(model.groups[first]?.tabs.count == 1)
        #expect(model.groups[second]?.tabs.count == 0)
        #expect(model.activeGroupID == first)
    }
}

// MARK: - Activity

@MainActor
@Suite("Pane groups: activity")
struct DKPaneTabActivityTests {
    @Test
    func `one tab is active in the whole area`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        model.openTab { tab("b") }
        #expect(model.tabActivity(groupID: g2, index: 0) == .active)
        #expect(model.tabActivity(groupID: g1, index: 0) == .frontUnfocused)

        model.focusGroup(g1)
        #expect(model.tabActivity(groupID: g1, index: 0) == .active)
        #expect(model.tabActivity(groupID: g2, index: 0) == .frontUnfocused)
        let actives = model.groupIDs.flatMap { id in
            (model.groups[id]?.tabs.indices ?? 0 ..< 0).map { model.tabActivity(groupID: id, index: $0) }
        }.filter { $0 == .active }
        #expect(actives.count == 1)
    }

    @Test
    func `tabs behind the front tab are inactive`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        model.openTab { tab("b") }
        let id = try #require(model.activeGroupID)
        #expect(model.tabActivity(groupID: id, index: 0) == .inactive)
        #expect(model.tabActivity(groupID: id, index: 1) == .active)
    }

    @Test
    func `activating ignores an index out of range`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        model.openTab { tab("b") }
        let id = try #require(model.activeGroupID)
        model.activateTab(groupID: id, index: 0)
        #expect(model.activeGroup?.activeIndex == 0)
        model.activateTab(groupID: id, index: 9)
        #expect(model.activeGroup?.activeIndex == 0)
    }
}

// MARK: - Closing

@MainActor
@Suite("Pane groups: closing")
struct DKPaneGroupsCloseTests {
    @Test
    func `the front tab index follows a removal`() {
        typealias Model = DKPaneGroupsModel<DKTestPayload>
        #expect(Model.adjustedActiveIndex(2, removedAt: 0, newCount: 3) == 1)
        #expect(Model.adjustedActiveIndex(1, removedAt: 1, newCount: 3) == 1)
        #expect(Model.adjustedActiveIndex(2, removedAt: 2, newCount: 2) == 1)
        #expect(Model.adjustedActiveIndex(0, removedAt: 2, newCount: 2) == 0)
        #expect(Model.adjustedActiveIndex(0, removedAt: 0, newCount: 0) == 0)
    }

    @Test
    func `the only group stays when its last tab closes`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        let id = try #require(model.activeGroupID)
        model.closeTab(groupID: id, index: 0)
        #expect(model.groupCount == 1)
        #expect(model.groups[id]?.tabs.isEmpty == true)
        #expect(model.activeGroupID == id)
        #expect(model.isEmpty)
    }

    @Test
    func `closing a group's last tab collapses the split`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        model.openTab { tab("b") }
        #expect(model.groupCount == 2)

        model.closeTab(groupID: g2, index: 0)
        #expect(model.groupCount == 1)
        #expect(model.groups[g2] == nil)
        #expect(model.activeGroupID == g1)
        #expect(model.root == .leaf(paneID: g1))
    }

    @Test
    func `without collapsing an emptied group stays`() throws {
        let model = makeModel(.init(collapsesEmptyGroups: false))
        model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        model.openTab { tab("b") }
        model.closeTab(groupID: g2, index: 0)
        #expect(model.groupCount == 2)
        #expect(model.groups[g2]?.tabs.isEmpty == true)
    }

    @Test
    func `the removal hook gets the tabs that remain`() throws {
        let model = makeModel()
        let calls = Calls<(UUID, [UUID])>()
        model.onTabRemoved = { removed, remaining in calls.values.append((removed.id, remaining.map(\.id))) }
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        let id = try #require(model.activeGroupID)
        model.closeTab(groupID: id, index: 0)
        #expect(calls.values.count == 1)
        #expect(calls.values.first?.0 == a)
        #expect(calls.values.first?.1 == [b])
    }

    @Test
    func `a shared document is released with its last tab`() throws {
        let model = makeModel()
        let released = Calls<UUID>()
        model.onTabRemoved = { removed, remaining in
            guard case let .table(_, doc) = removed.payload else { return }
            let used = remaining.contains {
                if case let .table(_, other) = $0.payload {
                    return other == doc
                }
                return false
            }
            if !used {
                released.values.append(doc)
            }
        }
        let doc = UUID()
        model.openTab { tab("users", doc: doc) }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        model.openTab { tab("users", doc: doc) }
        model.closeTab(groupID: g2, index: 0)
        #expect(released.values.isEmpty)
        model.closeTab(groupID: g1, index: 0)
        #expect(released.values == [doc])
    }

    @Test
    func `closing the active tab of an empty split closes the split`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        #expect(model.closeActiveTab())
        #expect(model.groupCount == 1)
        #expect(model.groups[g2] == nil)
    }

    @Test
    func `closing the active tab with nothing open reports it`() {
        let model = makeModel()
        #expect(!model.closeActiveTab())
        #expect(model.groupCount == 1)
    }

    @Test
    func `only an empty group that is not the last closes`() throws {
        let model = makeModel()
        let id = try #require(model.activeGroupID)
        #expect(!model.closeEmptyGroup(groupID: id))
        model.openTab { tab("a") }
        model.splitGroup(id)
        let other = try #require(model.activeGroupID)
        #expect(!model.closeEmptyGroup(groupID: id))
        #expect(model.closeEmptyGroup(groupID: other))
    }

    @Test
    func `closing by predicate sweeps every group`() throws {
        let model = makeModel()
        model.openTab { tab("users") }
        model.openTab { tab("orders") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        model.openTab { tab("users") }
        model.openTab { tab("logs") }
        model.closeTabs(where: named("users"))
        let names = model.allTabs.compactMap { tab -> String? in
            if case let .table(name, _) = tab.payload {
                return name
            }
            return nil
        }
        #expect(Set(names) == ["orders", "logs"])
    }

    @Test
    func `emptying the area calls its hook when the last group may not be empty`() throws {
        let model = makeModel(.init(allowsLastGroupEmpty: false))
        let calls = Calls<Void>()
        model.onAreaEmptied = { calls.values.append(()) }
        model.openTab { tab("a") }
        let id = try #require(model.activeGroupID)
        model.closeTab(groupID: id, index: 0)
        #expect(calls.values.count == 1)
    }
}

// MARK: - Layout

@MainActor
@Suite("Pane groups: layout")
struct DKPaneGroupsLayoutTests {
    @Test
    func `splitting opens an empty group beside by default`() throws {
        let model = makeModel()
        model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        #expect(g1 != g2)
        #expect(model.groups[g2]?.tabs.isEmpty == true)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.first == .leaf(paneID: g1))
        #expect(split.second == .leaf(paneID: g2))
    }

    @Test
    func `splitting seeds the new group when asked`() throws {
        let model = makeModel()
        model.makeTabForNewGroup = { DKPaneTab(payload: .scratch) }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1, direction: .vertical, newLeafFirst: true)
        let g2 = try #require(model.activeGroupID)
        #expect(model.groups[g2]?.tabs.first?.payload == .scratch)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split")
            return
        }
        #expect(split.direction == .vertical)
        #expect(split.first == .leaf(paneID: g2))
    }

    @Test
    func `the split limit applies to splitGroup only`() throws {
        let model = makeModel(.init(splitMaxGroups: 3))
        for _ in 0 ..< 3 {
            model.splitGroup(try #require(model.activeGroupID))
        }
        #expect(model.groupCount == 3)
        let target = try #require(model.groupIDs.first)
        model.openTab({ tab("a") }, in: target)
        model.openTab({ tab("b") }, in: target)
        let moving = try #require(model.groups[target]?.tabs.last?.id)
        model.moveTab(moving, toGroup: target, zone: .trailing)
        #expect(model.groupCount == 4)
    }

    @Test
    func `a splitter sets its split's fraction`() throws {
        let model = makeModel()
        model.splitGroup(try #require(model.activeGroupID))
        guard case let .split(split) = model.root else {
            Issue.record("expected a split")
            return
        }
        model.setFraction(0.7, splitID: split.id)
        guard case let .split(after) = model.root else {
            Issue.record("expected a split")
            return
        }
        #expect(abs(after.fraction - 0.7) < 0.0001)
    }

    @Test
    func `focusing an unknown group changes nothing`() throws {
        let model = makeModel()
        let id = try #require(model.activeGroupID)
        model.focusGroup(UUID())
        #expect(model.activeGroupID == id)
    }

    @Test
    func `reset leaves one empty group without the removal hook`() throws {
        let model = makeModel()
        let calls = Calls<Void>()
        model.onTabRemoved = { _, _ in calls.values.append(()) }
        model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        model.reset()
        #expect(model.groupCount == 1)
        #expect(model.groups.count == 1)
        #expect(model.isEmpty)
        #expect(calls.values.isEmpty)
    }
}

// MARK: - Dragging

@MainActor
@Suite("Pane groups: dragging")
struct DKPaneGroupsDragTests {
    @Test
    func `dropping on an edge splits the target`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: g1, zone: .trailing)
        #expect(model.groupCount == 2)
        let g2 = try #require(model.activeGroupID)
        #expect(model.groups[g2]?.tabs.map(\.id) == [a])
        #expect(model.groups[g1]?.tabs.count == 1)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.second == .leaf(paneID: g2))
    }

    @Test(arguments: [
        (DKPaneDropZone.leading, DKSplitDirection.horizontal, true),
        (.top, .vertical, true),
        (.bottom, .vertical, false),
        (.trailing, .horizontal, false),
    ])
    func `each edge splits on its side`(zone: DKPaneDropZone, direction: DKSplitDirection, newFirst: Bool) throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: g1, zone: zone)
        let g2 = try #require(model.activeGroupID)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split")
            return
        }
        #expect(split.direction == direction)
        #expect((newFirst ? split.first : split.second) == .leaf(paneID: g2))
    }

    @Test
    func `dropping on the center moves the tab and collapses its source`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        model.openTab { tab("b") }
        model.moveTab(a, toGroup: g2, zone: .center)
        #expect(model.groupCount == 1)
        #expect(model.groups[g1] == nil)
        #expect(model.groups[g2]?.tabs.last?.id == a)
        #expect(model.groups[g2]?.activeIndex == 1)
        #expect(model.activeGroupID == g2)
    }

    @Test
    func `dropping on its own group's center changes nothing`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: g1, zone: .center)
        #expect(model.groupCount == 1)
        #expect(model.groups[g1]?.tabs.first?.id == a)
    }

    @Test
    func `the only tab on its own edge is cloned`() throws {
        let model = makeModel()
        model.cloneTab = { source in
            guard case let .table(name, _) = source.payload else { return nil }
            return DKPaneTab(payload: .table(name, doc: UUID()))
        }
        let doc = UUID()
        let a = model.openTab { tab("users", doc: doc) }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: g1, zone: .trailing)
        #expect(model.groupCount == 2)
        #expect(model.groups[g1]?.tabs.first?.id == a)
        let g2 = try #require(model.activeGroupID)
        let clone = try #require(model.groups[g2]?.tabs.first)
        #expect(clone.id != a)
        #expect(clone.payload != .table("users", doc: doc))
    }

    @Test
    func `the only tab on its own edge stays without a clone hook`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: g1, zone: .trailing)
        #expect(model.groupCount == 1)
        #expect(model.groups[g1]?.tabs.count == 1)
    }

    @Test
    func `unknown tabs and groups are ignored`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.moveTab(a, toGroup: UUID(), zone: .center)
        model.moveTab(UUID(), toGroup: g1, zone: .trailing)
        #expect(model.groupCount == 1)
        #expect(model.groups[g1]?.tabs.count == 1)
    }

    @Test
    func `reordering within a group lands in the target's slot`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        let c = model.openTab { tab("c") }
        let id = try #require(model.activeGroupID)
        model.reorderTab(a, before: c)
        #expect(model.groups[id]?.tabs.map(\.id) == [b, a, c])
        #expect(model.groups[id]?.activeIndex == 1)
        model.reorderTab(c, before: b)
        #expect(model.groups[id]?.tabs.map(\.id) == [c, b, a])
        #expect(model.groups[id]?.activeIndex == 0)
    }

    @Test
    func `reordering into another group collapses an emptied source`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        let b = model.openTab { tab("b") }
        model.reorderTab(a, before: b)
        #expect(model.groupCount == 1)
        #expect(model.groups[g1] == nil)
        #expect(model.groups[g2]?.tabs.map(\.id) == [a, b])
        #expect(model.activeGroupID == g2)
    }

    @Test
    func `a tab dropped on itself stays`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let id = try #require(model.activeGroupID)
        model.reorderTab(a, before: a)
        #expect(model.groups[id]?.tabs.count == 1)
    }

    @Test
    func `tabs are found by id`() throws {
        let model = makeModel()
        let a = model.openTab { tab("a") }
        let g1 = try #require(model.activeGroupID)
        model.splitGroup(g1)
        let g2 = try #require(model.activeGroupID)
        let b = model.openTab { tab("b") }
        #expect(model.locateTab(a)?.groupID == g1)
        #expect(model.locateTab(a)?.index == 0)
        #expect(model.locateTab(b)?.groupID == g2)
        #expect(model.locateTab(UUID()) == nil)
        model.closeTab(b)
        #expect(model.groupCount == 1)
    }
}
