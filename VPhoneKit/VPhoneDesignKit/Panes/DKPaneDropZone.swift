import AppKit
import SwiftUI

// MARK: - Zones

/// The five places a tab can be dropped on a pane group:
/// - the center 50% × 50% moves the tab into that group;
/// - the top and bottom 25% bands split the group above or below;
/// - the leading and trailing 25% bands split it beside.
public enum DKPaneDropZone: String, Sendable, Hashable, Codable, CaseIterable {
    case center, top, bottom, leading, trailing

    /// The zone of a point in a group's own coordinates: the center, or the
    /// nearest edge. Nil for an empty rectangle.
    public static func at(_ location: CGPoint, in bounds: CGRect) -> DKPaneDropZone? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let x = (location.x - bounds.minX) / bounds.width
        let y = (location.y - bounds.minY) / bounds.height
        let edge = 0.25
        if x >= edge, x <= 1 - edge, y >= edge, y <= 1 - edge {
            return .center
        }
        let distances: [(DKPaneDropZone, CGFloat)] = [(.leading, x), (.trailing, 1 - x), (.top, y), (.bottom, 1 - y)]
        return distances.min { $0.1 < $1.1 }?.0
    }
}

/// Where a dragged tab is: a group and a zone of it.
public struct DKPaneDragHoverTarget: Equatable, Sendable {
    public let groupID: UUID
    public let zone: DKPaneDropZone

    public init(groupID: UUID, zone: DKPaneDropZone) {
        self.groupID = groupID
        self.zone = zone
    }
}

/// The zone a group highlights now, if any.
///
/// Only while a tab is being dragged: a hover can outlive the drag. And not
/// the center of the tab's own group, where a drop changes nothing; its edges
/// still split.
public func dkPaneDropHighlightZone(
    groupID: UUID,
    draggingTabID: UUID?,
    draggingSourceGroupID: UUID?,
    hover: DKPaneDragHoverTarget?,
) -> DKPaneDropZone? {
    guard draggingTabID != nil, let hover, hover.groupID == groupID else { return nil }
    if draggingSourceGroupID == groupID, hover.zone == .center {
        return nil
    }
    return hover.zone
}

// MARK: - Highlight

/// The drop hint over a group: an accent band along the edge and a tint over
/// the half a split would take, or a tinted outline for the center.
public struct DKPaneDropHighlight: View {
    public let zone: DKPaneDropZone

    public init(zone: DKPaneDropZone) {
        self.zone = zone
    }

    public var body: some View {
        GeometryReader { geometry in
            let color = DK.Palette.accent
            let band: CGFloat = 4
            switch zone {
            case .center:
                RoundedRectangle(cornerRadius: DK.Radius.menuItem, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: DK.Radius.menuItem, style: .continuous)
                            .fill(color.opacity(0.06)),
                    )
            case .top, .bottom:
                let alignment: Alignment = zone == .top ? .top : .bottom
                ZStack(alignment: alignment) {
                    color.opacity(0.10).frame(height: geometry.size.height / 2)
                    color.frame(height: band)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
            case .leading, .trailing:
                let alignment: Alignment = zone == .leading ? .leading : .trailing
                ZStack(alignment: alignment) {
                    color.opacity(0.10).frame(width: geometry.size.width / 2)
                    color.frame(width: band)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Splitter

/// The draggable divider between two groups: a hairline in the divider color
/// that turns accent while dragged, in a 6pt hit area with the resize cursor.
public struct DKPaneSplitter: View {
    /// Which way the line runs: a `vertical` line divides left from right and
    /// drags sideways.
    public enum Orientation: Sendable {
        case horizontal
        case vertical
    }

    public let orientation: Orientation
    @Binding public var fraction: Double
    public let totalLength: CGFloat
    public var minFraction: Double
    public var maxFraction: Double

    @State private var dragStartFraction: Double?

    public init(
        orientation: Orientation,
        fraction: Binding<Double>,
        totalLength: CGFloat,
        minFraction: Double = 0.15,
        maxFraction: Double = 0.85,
    ) {
        self.orientation = orientation
        _fraction = fraction
        self.totalLength = totalLength
        self.minFraction = minFraction
        self.maxFraction = maxFraction
    }

    /// The fraction after dragging `delta` points from `start`, within limits.
    public static func fraction(
        from start: Double,
        delta: CGFloat,
        totalLength: CGFloat,
        range: ClosedRange<Double> = 0.15 ... 0.85,
    ) -> Double {
        guard totalLength > 0 else { return start }
        return min(max(start + Double(delta / totalLength), range.lowerBound), range.upperBound)
    }

    public var body: some View {
        Color.clear
            .overlay {
                (dragStartFraction == nil ? DK.Palette.divider : DK.Palette.accent)
                    .frame(
                        width: orientation == .vertical ? DK.Metric.hairline : nil,
                        height: orientation == .horizontal ? DK.Metric.hairline : nil,
                    )
            }
            .frame(
                width: orientation == .vertical ? DKPaneLayout.splitterThickness : nil,
                height: orientation == .horizontal ? DKPaneLayout.splitterThickness : nil,
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (orientation == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            // Global coordinates: the splitter moves with the fraction, so a
            // local translation would be measured against a moving origin and
            // make the panes jitter.
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartFraction == nil {
                            dragStartFraction = fraction
                        }
                        let delta = orientation == .vertical ? value.translation.width : value.translation.height
                        fraction = Self.fraction(
                            from: dragStartFraction ?? fraction,
                            delta: delta,
                            totalLength: totalLength,
                            range: minFraction ... maxFraction,
                        )
                    }
                    .onEnded { _ in dragStartFraction = nil },
            )
            .accessibilityLabel(orientation == .vertical ? "Resize the panes side by side" : "Resize the stacked panes")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

// MARK: - Active Pane Gate

/// Whether the pane around a view is the one in front of the active group.
///
/// Every tab stays mounted, so a broadcast command (a menu item, a
/// notification) reaches hidden panes too; a pane acts on one only while its
/// gate is active. The gate is an object with a stable identity rather than a
/// Bool in the environment: flipping it re-evaluates only the views that read
/// it, not every pane's environment.
@MainActor
@Observable
public final class DKActivePaneGate {
    public var isActive: Bool

    public init(isActive: Bool) {
        self.isActive = isActive
    }
}

public extension EnvironmentValues {
    /// The gate `DKPaneGroupArea` gives each mounted pane; nil outside one.
    @Entry var dkActivePaneGate: DKActivePaneGate?
}
