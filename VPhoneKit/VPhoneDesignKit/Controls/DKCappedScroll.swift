import AppKit
import SwiftUI

/// A list that is as tall as its content up to a cap and scrolls inside past
/// it, for the content of a popover or a dropdown panel whose length depends on
/// data (machines, bundles, cores) and would otherwise run off the screen, with
/// the rows at the bottom out of sight and out of reach.
///
/// It does not use `ScrollView { … }.frame(maxHeight:)`: under a real proposal
/// `maxHeight` stretches to the smaller of the proposal and the cap, not to the
/// content, so a short list grows and its rows float in the middle. Instead it
/// measures the content and pins the height to the smaller of that and the cap.
///
/// The cap is `maxHeight` and never more than `DKCappedScroll.screenCap()`, the
/// height of the visible part of the main screen less a margin, so even an
/// uncapped list stays on screen.
///
/// ```swift
/// .popover(isPresented: $showsMachines) {
///     DKCappedScroll(maxHeight: 360, scrollTo: selection) {
///         ForEach(machines) { MachineRow($0).id($0.id) }
///     }
///     .frame(width: 280)
/// }
/// ```
///
/// Ported from uAppKit's `UDCappedScroll` and `UDMenu`.
public struct DKCappedScroll<Content: View>: View {
    let maxHeight: CGFloat?
    let scrollTarget: AnyHashable?
    let content: Content

    @State private var measured: CGFloat?
    @State private var didScrollToTarget = false

    /// - Parameters:
    ///   - maxHeight: The tallest the list grows before it scrolls, 360pt
    ///     (`defaultMaxHeight`) unless given; nil caps it
    ///     at the screen only.
    ///   - scrollTo: The id (`.id(_:)`) of a row to bring into view once the
    ///     list has its height, such as the selected one.
    public init(maxHeight: CGFloat? = 360, scrollTo: (some Hashable)? = String?.none, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        scrollTarget = scrollTo.map { AnyHashable($0) }
        self.content = content()
    }

    public var body: some View {
        let cap = DKCappedScrollMath.cap(maxHeight: maxHeight, screen: DKCappedScrollMath.screenCap())
        let overflows = (measured ?? 0) > cap
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Written on the next turn: writing here would make the
                    // pinned scroll view depend on its own measurement.
                    guard measured.map({ abs($0 - height) > 0.5 }) ?? true else {
                        return
                    }
                    DispatchQueue.main.async {
                        guard measured.map({ abs($0 - height) > 0.5 }) ?? true else {
                            return
                        }
                        measured = height
                    }
                }
            }
            .scrollIndicators(overflows ? .automatic : .never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: measured.map { DKCappedScrollMath.height(content: $0, cap: cap) })
            .frame(maxHeight: measured == nil ? cap : nil)
            .onChange(of: measured == nil) {
                // Once the first measurement has pinned the height; earlier,
                // the change of height would undo the scroll.
                guard !didScrollToTarget, overflows, let scrollTarget else {
                    return
                }
                didScrollToTarget = true
                DispatchQueue.main.async {
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
        }
    }
}

public extension DKCappedScroll where Content == EmptyView {
    /// The cap a list gets when none is given: about eleven rows.
    static var defaultMaxHeight: CGFloat {
        DKCappedScrollMath.defaultMaxHeight
    }

    /// The most a list can be on the main screen: its visible height (without
    /// the menu bar and the Dock) less 120pt for the panel around the list and
    /// the space to its anchor.
    @MainActor
    static func screenCap() -> CGFloat {
        DKCappedScrollMath.screenCap()
    }
}

/// The arithmetic behind `DKCappedScroll`, kept apart so tests can check it.
enum DKCappedScrollMath {
    static let defaultMaxHeight: CGFloat = 360

    /// The least height a cap leaves, however cramped the screen: two or three rows.
    static let minimumHeight: CGFloat = 64

    /// The pinned height: the content's, up to the cap.
    static func height(content: CGFloat, cap: CGFloat) -> CGFloat {
        max(0, min(content, cap))
    }

    /// The cap: `maxHeight` within the screen's, and never below `minimumHeight`.
    static func cap(maxHeight: CGFloat?, screen: CGFloat) -> CGFloat {
        max(min(maxHeight ?? .greatestFiniteMagnitude, screen), minimumHeight)
    }

    @MainActor
    static func screenCap() -> CGFloat {
        guard let visible = NSScreen.main?.visibleFrame else {
            return .greatestFiniteMagnitude
        }
        return max(visible.height - 120, minimumHeight)
    }
}
