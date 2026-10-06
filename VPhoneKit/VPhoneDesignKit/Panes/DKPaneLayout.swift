import CoreGraphics
import Foundation

// MARK: - Tree

/// How a split divides its space: `horizontal` puts its two children side by
/// side, `vertical` stacks them.
public enum DKSplitDirection: String, Codable, Sendable, Equatable {
    case horizontal
    case vertical
}

/// One split: two children and the share of the first, from 0 to 1.
public struct DKSplitNode: Equatable, Sendable {
    public let id: UUID
    public var direction: DKSplitDirection
    public var fraction: Double
    public var first: DKPaneLayout
    public var second: DKPaneLayout

    public init(id: UUID, direction: DKSplitDirection, fraction: Double, first: DKPaneLayout, second: DKPaneLayout) {
        self.id = id
        self.direction = direction
        self.fraction = fraction
        self.first = first
        self.second = second
    }
}

/// A binary split tree whose leaves are panes, named by id; the caller says
/// what a pane holds. A value: every operation returns a new tree.
///
/// Ported from uAppKit's `LayoutNode`.
public indirect enum DKPaneLayout: Equatable, Sendable {
    case leaf(paneID: UUID)
    case split(DKSplitNode)

    /// Every pane, depth first.
    public var leafIDs: [UUID] {
        switch self {
        case let .leaf(id): [id]
        case let .split(split): split.first.leafIDs + split.second.leafIDs
        }
    }

    public var firstLeafID: UUID? {
        leafIDs.first
    }

    public var leafCount: Int {
        switch self {
        case .leaf: 1
        case let .split(split): split.first.leafCount + split.second.leafCount
        }
    }

    public var isSingleLeaf: Bool {
        if case .leaf = self {
            return true
        }
        return false
    }

    /// Replaces the pane `paneID` with a split of it and a new pane, the new
    /// one first when `newLeafFirst`.
    public func splitting(
        paneID: UUID,
        direction: DKSplitDirection,
        newPaneID: UUID,
        splitID: UUID,
        fraction: Double = 0.5,
        newLeafFirst: Bool = false,
    ) -> DKPaneLayout {
        switch self {
        case let .leaf(id):
            guard id == paneID else { return self }
            let original = DKPaneLayout.leaf(paneID: id)
            let added = DKPaneLayout.leaf(paneID: newPaneID)
            return .split(DKSplitNode(
                id: splitID,
                direction: direction,
                fraction: fraction,
                first: newLeafFirst ? added : original,
                second: newLeafFirst ? original : added,
            ))
        case var .split(split):
            split.first = split.first.splitting(
                paneID: paneID, direction: direction, newPaneID: newPaneID,
                splitID: splitID, fraction: fraction, newLeafFirst: newLeafFirst,
            )
            split.second = split.second.splitting(
                paneID: paneID, direction: direction, newPaneID: newPaneID,
                splitID: splitID, fraction: fraction, newLeafFirst: newLeafFirst,
            )
            return .split(split)
        }
    }

    /// Swaps two panes, keeping the tree's shape and fractions. Nothing
    /// changes unless both are in the tree.
    public func swapping(_ a: UUID, _ b: UUID) -> DKPaneLayout {
        guard a != b else { return self }
        let ids = leafIDs
        guard ids.contains(a), ids.contains(b) else { return self }
        return swappingKnown(a, b)
    }

    private func swappingKnown(_ a: UUID, _ b: UUID) -> DKPaneLayout {
        switch self {
        case let .leaf(id):
            if id == a {
                return .leaf(paneID: b)
            }
            if id == b {
                return .leaf(paneID: a)
            }
            return self
        case var .split(split):
            split.first = split.first.swappingKnown(a, b)
            split.second = split.second.swappingKnown(a, b)
            return .split(split)
        }
    }

    /// Removes a pane; its sibling takes the parent split's place. Nil when
    /// it was the tree's only pane.
    public func removingLeaf(paneID: UUID) -> DKPaneLayout? {
        switch self {
        case let .leaf(id):
            return id == paneID ? nil : self
        case var .split(split):
            // Recurse only into the side that holds the pane: the other side
            // returns itself, which would look like a successful removal.
            if split.first.leafIDs.contains(paneID) {
                guard let first = split.first.removingLeaf(paneID: paneID) else { return split.second }
                split.first = first
                return .split(split)
            }
            if split.second.leafIDs.contains(paneID) {
                guard let second = split.second.removingLeaf(paneID: paneID) else { return split.first }
                split.second = second
                return .split(split)
            }
            return .split(split)
        }
    }

    public func settingFraction(_ fraction: Double, splitID: UUID) -> DKPaneLayout {
        switch self {
        case .leaf:
            return self
        case var .split(split):
            if split.id == splitID {
                split.fraction = fraction
            } else {
                split.first = split.first.settingFraction(fraction, splitID: splitID)
                split.second = split.second.settingFraction(fraction, splitID: splitID)
            }
            return .split(split)
        }
    }
}

// MARK: - Frames

/// One pane's rectangle in the container.
public struct DKPaneFrame: Equatable, Sendable {
    public let paneID: UUID
    public let rect: CGRect

    public init(paneID: UUID, rect: CGRect) {
        self.paneID = paneID
        self.rect = rect
    }
}

/// One splitter's rectangle, with its split's fraction and the length along
/// the split, which turns a drag distance into a fraction.
public struct DKSplitterFrame: Equatable, Sendable {
    /// Where the splitter takes drags: its line widened to
    /// `DKPaneLayout.splitterThickness` across the line, over both panes.
    public var hitRect: CGRect {
        let grow = (DKPaneLayout.splitterThickness - (direction == .horizontal ? rect.width : rect.height)) / 2
        return direction == .horizontal
            ? rect.insetBy(dx: -max(grow, 0), dy: 0)
            : rect.insetBy(dx: 0, dy: -max(grow, 0))
    }

    public let splitID: UUID
    public let direction: DKSplitDirection
    public let rect: CGRect
    public let fraction: Double
    public let totalLength: CGFloat

    public init(splitID: UUID, direction: DKSplitDirection, rect: CGRect, fraction: Double, totalLength: CGFloat) {
        self.splitID = splitID
        self.direction = direction
        self.rect = rect
        self.fraction = fraction
        self.totalLength = totalLength
    }
}

/// A whole tree laid out flat.
public struct DKPaneLayoutFrames: Equatable, Sendable {
    public var panes: [DKPaneFrame] = []
    public var splitters: [DKSplitterFrame] = []

    public init(panes: [DKPaneFrame] = [], splitters: [DKSplitterFrame] = []) {
        self.panes = panes
        self.splitters = splitters
    }
}

public extension DKPaneLayout {
    /// The room between two panes: the splitter's one-point line, so the
    /// panes meet at a hairline with no gap.
    static let dividerThickness: CGFloat = DK.Metric.hairline

    /// The splitter's drag area, centered on its line and reaching over
    /// the panes on both sides.
    static let splitterThickness: CGFloat = 6

    /// One rectangle per pane and per splitter.
    ///
    /// The pane area draws every pane in one flat ZStack from these instead of
    /// nesting pane views in split containers: nested, a split or a merge
    /// changes each pane's place in the view tree and SwiftUI rebuilds it. Flat,
    /// a pane's identity is its id, and a split only changes frames.
    func frames(in rect: CGRect) -> DKPaneLayoutFrames {
        var frames = DKPaneLayoutFrames()
        accumulate(into: &frames, rect: rect)
        return frames
    }

    private func accumulate(into frames: inout DKPaneLayoutFrames, rect: CGRect) {
        switch self {
        case let .leaf(paneID):
            frames.panes.append(DKPaneFrame(paneID: paneID, rect: rect))
        case let .split(split):
            let thickness = DKPaneLayout.dividerThickness
            let total = split.direction == .horizontal ? rect.width : rect.height
            let firstLength = max(0, total * split.fraction)
            let secondLength = max(0, total - firstLength - thickness)
            if split.direction == .horizontal {
                split.first.accumulate(into: &frames, rect: CGRect(
                    x: rect.minX, y: rect.minY, width: firstLength, height: rect.height,
                ))
                frames.splitters.append(DKSplitterFrame(
                    splitID: split.id, direction: .horizontal,
                    rect: CGRect(x: rect.minX + firstLength, y: rect.minY, width: thickness, height: rect.height),
                    fraction: split.fraction, totalLength: total,
                ))
                split.second.accumulate(into: &frames, rect: CGRect(
                    x: rect.minX + firstLength + thickness, y: rect.minY, width: secondLength, height: rect.height,
                ))
            } else {
                split.first.accumulate(into: &frames, rect: CGRect(
                    x: rect.minX, y: rect.minY, width: rect.width, height: firstLength,
                ))
                frames.splitters.append(DKSplitterFrame(
                    splitID: split.id, direction: .vertical,
                    rect: CGRect(x: rect.minX, y: rect.minY + firstLength, width: rect.width, height: thickness),
                    fraction: split.fraction, totalLength: total,
                ))
                split.second.accumulate(into: &frames, rect: CGRect(
                    x: rect.minX, y: rect.minY + firstLength + thickness, width: rect.width, height: secondLength,
                ))
            }
        }
    }
}
