import Testing
@testable import VPhoneDesignKit

/// Tab strip selection, closing and preview tabs.
@Suite("DesignKit tab strip")
struct DKTabStripTests {
    private func tabs(_ ids: String...) -> [DKTab<String>] {
        ids.map { DKTab(id: $0, title: $0) }
    }

    @Test
    func `closing the selected tab selects its right neighbor`() {
        var list = tabs("a", "b", "c")
        let next = list.closeTab("b", selection: "b")
        #expect(next == "c")
        #expect(list.map(\.id) == ["a", "c"])
    }

    @Test
    func `closing the selected last tab selects its left neighbor`() {
        var list = tabs("a", "b", "c")
        #expect(list.closeTab("c", selection: "c") == "b")
        #expect(list.map(\.id) == ["a", "b"])
    }

    @Test
    func `closing the only tab leaves nothing selected`() {
        var list = tabs("a")
        #expect(list.closeTab("a", selection: "a") == nil)
        #expect(list.isEmpty)
    }

    @Test
    func `closing another tab keeps the selection`() {
        var list = tabs("a", "b", "c")
        #expect(list.closeTab("a", selection: "c") == "c")
        #expect(list.map(\.id) == ["b", "c"])
    }

    @Test
    func `a tab that is not closable stays`() {
        var list = [DKTab(id: "display", title: "Display", isClosable: false)] + tabs("b")
        #expect(list.closeTab("display", selection: "display") == "display")
        #expect(list.map(\.id) == ["display", "b"])
    }

    @Test
    func `closing a tab that is not there changes nothing`() {
        var list = tabs("a", "b")
        #expect(list.closeTab("z", selection: "a") == "a")
        #expect(list.map(\.id) == ["a", "b"])
    }

    @Test
    func `a new preview replaces the current preview in place`() {
        var list = tabs("a")
        list.openTab(DKTab(id: "p1", title: "one.md", isTransient: true))
        list.append(DKTab(id: "b", title: "b"))
        let selected = list.openTab(DKTab(id: "p2", title: "two.md", isTransient: true))
        #expect(selected == "p2")
        #expect(list.map(\.id) == ["a", "p2", "b"])
        #expect(list.filter(\.isTransient).count == 1)
    }

    @Test
    func `opening a permanent tab appends it, and reopening keeps a preview`() {
        var list = tabs("a")
        list.openTab(DKTab(id: "p", title: "p.md", isTransient: true))
        #expect(list.openTab(DKTab(id: "b", title: "b")) == "b")
        #expect(list.map(\.id) == ["a", "p", "b"])

        #expect(list.openTab(DKTab(id: "p", title: "p.md")) == "p")
        #expect(list.map(\.id) == ["a", "p", "b"])
        #expect(list.allSatisfy { !$0.isTransient })
    }

    @Test
    func `reopening a tab as a preview does not demote it`() {
        var list = tabs("a")
        #expect(list.openTab(DKTab(id: "a", title: "a", isTransient: true)) == "a")
        #expect(list.count == 1)
        #expect(!list[0].isTransient)
    }

    @Test
    func `keeping a preview makes it permanent`() {
        var list = [DKTab(id: "p", title: "p.md", isTransient: true)]
        list.keepTab("p")
        #expect(!list[0].isTransient)
    }
}
