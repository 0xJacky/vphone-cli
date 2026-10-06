import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import VPhoneDesignKit

/// What the area view does that can be observed: content is mounted flat,
/// once per tab, so splitting, moving and collapsing keep each pane's view.
/// A marker NSView stands in for the content, so mounted panes can be counted
/// and their identity compared across a change.
///
/// Not testable here: a real drag session (`onDrag` and the drop delegates run
/// only in AppKit's drag loop under a real mouse) and the pointer-down probe.
/// Ported from uAppKit's UPaneGroupAreaViewTests.
@MainActor
@Suite("Pane group area", .serialized)
struct DKPaneGroupAreaTests {
    final class MarkerView: NSView {
        let tabID: UUID

        init(tabID: UUID) {
            self.tabID = tabID
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }

    struct Marker: NSViewRepresentable {
        let tabID: UUID

        func makeNSView(context _: Context) -> MarkerView {
            MarkerView(tabID: tabID)
        }

        func updateNSView(_: MarkerView, context _: Context) {}
    }

    private func markers(in view: NSView) -> [MarkerView] {
        (view as? MarkerView).map { [$0] } ?? view.subviews.flatMap { markers(in: $0) }
    }

    /// The view has to be in a window and the run loop has to turn before
    /// representables exist.
    private func host(_ view: some View) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        settle(host, window)
        return (window, host)
    }

    private func settle(_ host: NSView, _ window: NSWindow) {
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func tab(_ name: String) -> DKPaneTab<String> {
        DKPaneTab(payload: name)
    }

    private func area(_ model: DKPaneGroupsModel<String>) -> some View {
        DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload, glyph: .terminal) },
            onRequestClose: { model.closeTab($0.id) },
            content: { tab, _ in Marker(tabID: tab.id) },
            emptyGroup: { _ in Color.clear },
        )
    }

    // MARK: Mounting

    @Test
    func `every tab is mounted once, behind tabs included`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let mounted = markers(in: host)
        #expect(Set(mounted.map(\.tabID)) == [a, b, c])
        #expect(mounted.count == 3)
    }

    @Test
    func `keeping only front tabs mounts one per group`() throws {
        let model = DKPaneGroupsModel<String>(policy: .init(keepAlive: .activeTabPerGroup))
        model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(Set(markers(in: host).map(\.tabID)) == [b, c])
    }

    @Test
    func `keeping only the active group mounts one tab`() throws {
        let model = DKPaneGroupsModel<String>(policy: .init(keepAlive: .activeGroupOnly))
        model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(markers(in: host).map(\.tabID) == [c])
    }

    @Test
    func `an empty group mounts nothing`() {
        let model = DKPaneGroupsModel<String>()
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(markers(in: host).isEmpty)
    }

    // MARK: Identity Across Changes

    @Test
    func `splitting keeps the mounted pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let group = try #require(model.activeGroupID)
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.splitGroup(group)
        settle(host, window)
        let after = try #require(markers(in: host).first { $0.tabID == a })
        #expect(before === after)
    }

    @Test
    func `moving a tab to another group keeps its pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let target = try #require(model.activeGroupID)
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.moveTab(a, toGroup: target, zone: .center)
        settle(host, window)
        let after = try #require(markers(in: host).first { $0.tabID == a })
        #expect(before === after)
        #expect(model.locateTab(a)?.groupID == target)
    }

    @Test
    func `collapsing a split keeps the surviving pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let b = model.openTab { tab("b") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.closeTab(b)
        settle(host, window)
        #expect(model.groupCount == 1)
        let remaining = markers(in: host)
        #expect(remaining.map(\.tabID) == [a])
        #expect(remaining.first === before)
    }

    @Test
    func `content wider than its pane stays inside it`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let b = model.openTab { tab("b") }
        let view = DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload) },
            onRequestClose: { _ in },
            content: { tab, _ in Marker(tabID: tab.id).frame(minWidth: 600) },
            emptyGroup: { _ in Color.clear },
        )
        let (window, host) = host(view.frame(width: 800, height: 600))
        defer { window.contentView = nil }
        let frames = Dictionary(uniqueKeysWithValues: markers(in: host).map { ($0.tabID, $0.convert($0.bounds, to: nil)) })
        let left = try #require(frames[a])
        let right = try #require(frames[b])
        #expect(abs(left.width - 600) < 0.5)
        #expect(abs(left.minX) < 0.5)
        #expect(right.minX >= 400 - 4)
    }

    // MARK: Active Pane Gate

    @Test
    func `each pane's gate follows the active tab`() throws {
        final class Seen: @unchecked Sendable {
            var gates: [UUID: DKActivePaneGate] = [:]
        }
        struct Probe: View {
            let tabID: UUID
            let seen: Seen
            @Environment(\.dkActivePaneGate) private var gate

            var body: some View {
                Color.clear.onAppear {
                    if let gate {
                        seen.gates[tabID] = gate
                    }
                }
            }
        }
        let seen = Seen()
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        let group = try #require(model.activeGroupID)
        let view = DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload) },
            onRequestClose: { _ in },
            content: { tab, _ in Probe(tabID: tab.id, seen: seen) },
            emptyGroup: { _ in Color.clear },
        )
        let (window, host) = host(view)
        defer { window.contentView = nil }
        let gateA = try #require(seen.gates[a])
        let gateB = try #require(seen.gates[b])
        #expect(gateA !== gateB)
        #expect(!gateA.isActive)
        #expect(gateB.isActive)

        model.activateTab(groupID: group, index: 0)
        settle(host, window)
        #expect(gateA.isActive)
        #expect(!gateB.isActive)
        #expect(seen.gates[a] === gateA)

        // A front tab in a group without focus is not the active pane.
        model.splitGroup(group)
        model.openTab { tab("c") }
        settle(host, window)
        #expect(!gateA.isActive)
    }

}
