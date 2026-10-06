import CoreGraphics
import Foundation
import Observation
import Testing
import UniformTypeIdentifiers
@testable import VPhoneDesignKit

// MARK: - Tree

/// Ported from uAppKit's LayoutNodeTests and LayoutFramesTests.
@Suite("Pane layout tree")
struct DKPaneLayoutTests {
    @Test
    func `a leaf lists itself`() {
        let a = UUID()
        let tree = DKPaneLayout.leaf(paneID: a)
        #expect(tree.leafIDs == [a])
        #expect(tree.firstLeafID == a)
        #expect(tree.isSingleLeaf)
        #expect(tree.leafCount == 1)
    }

    @Test
    func `splitting a leaf puts the new pane second, or first when asked`() {
        let a = UUID(), b = UUID(), split = UUID()
        let after = DKPaneLayout.leaf(paneID: a).splitting(paneID: a, direction: .vertical, newPaneID: b, splitID: split)
        #expect(after == .split(DKSplitNode(id: split, direction: .vertical, fraction: 0.5, first: .leaf(paneID: a), second: .leaf(paneID: b))))
        #expect(!after.isSingleLeaf)
        let first = DKPaneLayout.leaf(paneID: a).splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: split, newLeafFirst: true)
        #expect(first.leafIDs == [b, a])
    }

    @Test
    func `splitting reaches a nested pane only`() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: UUID())
            .splitting(paneID: b, direction: .vertical, newPaneID: c, splitID: UUID())
        #expect(tree.leafIDs == [a, b, c])
        #expect(tree.leafCount == 3)
    }

    @Test
    func `removing a pane promotes its sibling`() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: UUID())
            .splitting(paneID: b, direction: .vertical, newPaneID: c, splitID: UUID())
        let without = tree.removingLeaf(paneID: b)
        #expect(without?.leafIDs == [a, c])
        #expect(without?.removingLeaf(paneID: c) == .leaf(paneID: a))
        #expect(DKPaneLayout.leaf(paneID: a).removingLeaf(paneID: a) == nil)
        #expect(tree.removingLeaf(paneID: UUID()) == tree)
    }

    @Test
    func `a fraction is set on its own split`() {
        let a = UUID(), b = UUID(), c = UUID(), outer = UUID(), inner = UUID()
        let tree = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: outer)
            .splitting(paneID: b, direction: .vertical, newPaneID: c, splitID: inner)
            .settingFraction(0.3, splitID: inner)
        guard case let .split(root) = tree, case let .split(nested) = root.second else {
            Issue.record("expected nested splits")
            return
        }
        #expect(root.fraction == 0.5)
        #expect(nested.fraction == 0.3)
    }

    @Test
    func `swapping exchanges two panes and keeps the shape`() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: UUID())
            .splitting(paneID: b, direction: .vertical, newPaneID: c, splitID: UUID())
        #expect(tree.swapping(a, c).leafIDs == [c, b, a])
        #expect(tree.swapping(a, UUID()) == tree)
        #expect(tree.swapping(a, a) == tree)
    }
}

// MARK: - Frames

@Suite("Pane layout frames")
struct DKPaneLayoutFramesTests {
    @Test
    func `a single pane fills the rectangle`() {
        let a = UUID()
        let frames = DKPaneLayout.leaf(paneID: a).frames(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frames.panes == [DKPaneFrame(paneID: a, rect: CGRect(x: 0, y: 0, width: 800, height: 600))])
        #expect(frames.splitters.isEmpty)
    }

    @Test
    func `a split leaves a hairline between its panes`() {
        let a = UUID(), b = UUID(), split = UUID()
        let thickness = DKPaneLayout.dividerThickness
        #expect(thickness == 1)
        let frames = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: split)
            .frames(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frames.panes.map(\.paneID) == [a, b])
        #expect(frames.panes[0].rect == CGRect(x: 0, y: 0, width: 400, height: 600))
        #expect(frames.panes[1].rect == CGRect(x: 400 + thickness, y: 0, width: 400 - thickness, height: 600))
        #expect(frames.splitters.count == 1)
        #expect(frames.splitters[0].splitID == split)
        #expect(frames.splitters[0].totalLength == 800)
        #expect(frames.splitters[0].rect == CGRect(x: 400, y: 0, width: thickness, height: 600))
        // The drag area reaches over both panes, centered on the line.
        #expect(frames.splitters[0].hitRect == CGRect(x: 397.5, y: 0, width: DKPaneLayout.splitterThickness, height: 600))
    }

    @Test
    func `a stacked split's drag area widens vertically`() {
        let a = UUID(), b = UUID()
        let frames = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .vertical, newPaneID: b, splitID: UUID())
            .frames(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frames.splitters[0].rect == CGRect(x: 0, y: 300, width: 800, height: 1))
        #expect(frames.splitters[0].hitRect == CGRect(x: 0, y: 297.5, width: 800, height: 6))
        #expect(frames.panes[1].rect.minY == 301)
    }

    @Test
    func `nested splits stay inside their parent`() {
        let a = UUID(), b = UUID(), c = UUID()
        let frames = DKPaneLayout.leaf(paneID: a)
            .splitting(paneID: a, direction: .horizontal, newPaneID: b, splitID: UUID())
            .splitting(paneID: b, direction: .vertical, newPaneID: c, splitID: UUID())
            .frames(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frames.panes.map(\.paneID) == [a, b, c])
        for pane in frames.panes {
            #expect(pane.rect.maxX <= 800)
            #expect(pane.rect.maxY <= 600)
        }
        #expect(frames.panes[1].rect.minX == frames.panes[2].rect.minX)
        #expect(frames.panes[1].rect.maxY < frames.panes[2].rect.minY)
    }
}

// MARK: - Drop Zones

/// Ported from uAppKit's UPaneDropZoneTests.
@Suite("Pane drop zones")
struct DKPaneDropZoneTests {
    @Test
    func `points fall into the center or the nearest edge`() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(DKPaneDropZone.at(CGPoint(x: 50, y: 50), in: bounds) == .center)
        #expect(DKPaneDropZone.at(CGPoint(x: 5, y: 50), in: bounds) == .leading)
        #expect(DKPaneDropZone.at(CGPoint(x: 95, y: 50), in: bounds) == .trailing)
        #expect(DKPaneDropZone.at(CGPoint(x: 50, y: 5), in: bounds) == .top)
        #expect(DKPaneDropZone.at(CGPoint(x: 50, y: 95), in: bounds) == .bottom)
        // The center is exactly 50% × 50%, its edges included.
        #expect(DKPaneDropZone.at(CGPoint(x: 25, y: 25), in: bounds) == .center)
        #expect(DKPaneDropZone.at(CGPoint(x: 75, y: 75), in: bounds) == .center)
        #expect(DKPaneDropZone.at(.zero, in: .zero) == nil)
        #expect(DKPaneDropZone.at(.zero, in: CGRect(x: 0, y: 0, width: 10, height: 0)) == nil)
    }

    @Test
    func `zones follow the rectangle's origin`() {
        let bounds = CGRect(x: 100, y: 200, width: 100, height: 100)
        #expect(DKPaneDropZone.at(CGPoint(x: 150, y: 250), in: bounds) == .center)
        #expect(DKPaneDropZone.at(CGPoint(x: 105, y: 250), in: bounds) == .leading)
    }

    @Test
    func `only a real drag highlights, and never its own group's center`() {
        let group = UUID(), other = UUID(), tab = UUID()
        #expect(dkPaneDropHighlightZone(
            groupID: group, draggingTabID: nil, draggingSourceGroupID: nil,
            hover: DKPaneDragHoverTarget(groupID: group, zone: .top),
        ) == nil)
        #expect(dkPaneDropHighlightZone(
            groupID: group, draggingTabID: tab, draggingSourceGroupID: group,
            hover: DKPaneDragHoverTarget(groupID: group, zone: .center),
        ) == nil)
        #expect(dkPaneDropHighlightZone(
            groupID: group, draggingTabID: tab, draggingSourceGroupID: group,
            hover: DKPaneDragHoverTarget(groupID: group, zone: .trailing),
        ) == .trailing)
        #expect(dkPaneDropHighlightZone(
            groupID: other, draggingTabID: tab, draggingSourceGroupID: group,
            hover: DKPaneDragHoverTarget(groupID: other, zone: .center),
        ) == .center)
        #expect(dkPaneDropHighlightZone(
            groupID: group, draggingTabID: tab, draggingSourceGroupID: group,
            hover: DKPaneDragHoverTarget(groupID: other, zone: .top),
        ) == nil)
    }

    @Test
    func `a splitter drag turns points into a bounded fraction`() {
        #expect(abs(DKPaneSplitter.fraction(from: 0.5, delta: 100, totalLength: 1000) - 0.6) < 1e-9)
        #expect(DKPaneSplitter.fraction(from: 0.5, delta: -900, totalLength: 1000) == 0.15)
        #expect(DKPaneSplitter.fraction(from: 0.5, delta: 900, totalLength: 1000) == 0.85)
        #expect(DKPaneSplitter.fraction(from: 0.4, delta: 50, totalLength: 0) == 0.4)
    }
}

// MARK: - Drag Session

@MainActor
@Suite("Pane drag session")
struct DKPaneDragStateTests {
    private final class Counter: @unchecked Sendable {
        var count = 0
    }

    @Test
    func `an unchanged hover is not written again`() {
        let counter = Counter()
        let state = DKPaneDragState()
        let group = UUID()
        func observe() {
            withObservationTracking { _ = state.hover } onChange: { counter.count += 1 }
        }
        observe()
        state.setHover(DKPaneDragHoverTarget(groupID: group, zone: .center))
        #expect(counter.count == 1)
        observe()
        state.setHover(DKPaneDragHoverTarget(groupID: group, zone: .center))
        #expect(counter.count == 1)
        state.setHover(DKPaneDragHoverTarget(groupID: group, zone: .trailing))
        #expect(counter.count == 2)
    }

    @Test
    func `begin and end track the dragged tab`() {
        let state = DKPaneDragState()
        let tab = UUID(), group = UUID()
        state.begin(tabID: tab, groupID: group)
        #expect(state.draggingTabID == tab)
        #expect(state.draggingSourceGroupID == group)
        #expect(state.hover == nil)
        state.setHover(DKPaneDragHoverTarget(groupID: group, zone: .top))
        state.end()
        #expect(state.draggingTabID == nil)
        #expect(state.draggingSourceGroupID == nil)
        #expect(state.hover == nil)
        state.end()
        #expect(state.draggingTabID == nil)
    }

    @Test
    func `group sizes are read live, not captured`() {
        let state = DKPaneDragState()
        let group = UUID()
        state.groupBounds[group] = CGRect(x: 0, y: 0, width: 100, height: 100)
        let read = { state.groupBounds[group] ?? .zero }
        state.groupBounds[group] = CGRect(x: 0, y: 0, width: 400, height: 100)
        #expect(read().width == 400)
    }

    @Test
    func `a tab id survives the item provider`() async {
        let id = UUID()
        let provider = DKPaneTabDragPayload.itemProvider(tabID: id, type: .plainText)
        let loaded = await withCheckedContinuation { continuation in
            DKPaneTabDragPayload.load(from: provider, type: .plainText) { continuation.resume(returning: $0) }
        }
        #expect(loaded == id)
    }
}
