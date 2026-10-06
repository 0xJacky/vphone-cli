import SwiftUI

// MARK: - Inspector column

/// A page's trailing inspector, drawn by the page under its own header
/// rather than by a system split view beside the whole window: the content
/// at `width`, behind a one-point divider on its leading edge. Dragging the
/// divider resizes the column within `widthRange`; dragging left widens it.
///
/// ```swift
/// HStack(spacing: 0) {
///     table
///     if showsInspector {
///         DKInspectorColumn(width: $inspectorWidth) { inspector }
///     }
/// }
/// ```
public struct DKInspectorColumn<Content: View>: View {
    /// The width a column starts at.
    public nonisolated static var idealWidth: CGFloat {
        380
    }

    public nonisolated static var widthRange: ClosedRange<CGFloat> {
        300 ... 520
    }

    /// The width a drag of `translation` from `start` asks for, kept in range.
    nonisolated static func width(from start: CGFloat, dragged translation: CGFloat) -> CGFloat {
        min(max(start - translation, widthRange.lowerBound), widthRange.upperBound)
    }

    @Binding var width: CGFloat
    let content: Content
    @State private var dragStart: CGFloat?

    public init(width: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        _width = width
        self.content = content()
    }

    public var body: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DK.Palette.divider)
                    .frame(width: DK.Metric.hairline)
                    .frame(maxHeight: .infinity)
                    .overlay { handle }
            }
    }

    /// A few points either side of the divider take the drag.
    private var handle: some View {
        Color.clear
            .frame(width: 7)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? width
                        dragStart = start
                        width = Self.width(from: start, dragged: drag.translation.width)
                    }
                    .onEnded { _ in dragStart = nil },
            )
    }
}
