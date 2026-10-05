import SwiftUI

// MARK: - Note

/// How a sheet's footer note reads: plain, a caution, or a failure.
public enum DKSheetNoteTone: String, Sendable, CaseIterable, Hashable {
    case muted
    case warning
    case danger

    /// The note tone for a status tone: warning and danger keep theirs, every
    /// other tone reads as muted.
    public init(_ tone: DKTone) {
        switch tone {
        case .warning: self = .warning
        case .danger: self = .danger
        case .neutral, .idle, .success, .info, .accent: self = .muted
        }
    }

    /// The status tone whose ink colors the note.
    public var tone: DKTone {
        switch self {
        case .muted: .idle
        case .warning: .warning
        case .danger: .danger
        }
    }

    /// The note's text color.
    public var color: Color {
        tone.ink
    }
}

/// A line of text in a sheet's footer, before the trailing buttons: what the
/// primary action will do, or why it cannot.
public struct DKSheetNote: Sendable, Hashable {
    public var text: String
    public var tone: DKSheetNoteTone

    public init(_ text: String, tone: DKSheetNoteTone = .muted) {
        self.text = text
        self.tone = tone
    }
}

// MARK: - Actions

/// Which key a sheet button answers. `automatic` gives Return to the first
/// `primary` button when no button claims it; `plain` never takes a key.
public enum DKSheetActionRole: Sendable, Hashable {
    case automatic
    case defaultAction
    case cancel
    case plain
}

/// The key a sheet button is bound to.
public enum DKSheetShortcut: Sendable, Hashable {
    /// Return.
    case defaultAction
    /// Escape.
    case cancelAction

    public var keyboardShortcut: KeyboardShortcut {
        switch self {
        case .defaultAction: .defaultAction
        case .cancelAction: .cancelAction
        }
    }
}

/// A button in a sheet's footer: a `DKButtonSpec` and the key it answers.
public struct DKSheetAction: Identifiable {
    public var spec: DKButtonSpec
    public var role: DKSheetActionRole

    public var id: String {
        spec.id
    }

    public init(_ spec: DKButtonSpec, role: DKSheetActionRole = .automatic) {
        self.spec = spec
        self.role = role
    }

    public init(
        _ label: String,
        glyph: DKGlyph? = nil,
        variant: DKButtonVariant = .secondary,
        role: DKSheetActionRole = .automatic,
        isEnabled: Bool = true,
        help: String? = nil,
        id: String? = nil,
        action: @escaping () -> Void,
    ) {
        self.init(
            DKButtonSpec(label, glyph: glyph, variant: variant, isEnabled: isEnabled, help: help, id: id, action: action),
            role: role,
        )
    }

    /// The sheet's default action: a primary button bound to Return.
    public static func primary(
        _ label: String,
        isEnabled: Bool = true,
        help: String? = nil,
        action: @escaping () -> Void,
    ) -> DKSheetAction {
        DKSheetAction(label, variant: .primary, role: .defaultAction, isEnabled: isEnabled, help: help, action: action)
    }

    /// A destructive default action: a danger button bound to Return.
    public static func destructive(
        _ label: String,
        isEnabled: Bool = true,
        help: String? = nil,
        action: @escaping () -> Void,
    ) -> DKSheetAction {
        DKSheetAction(label, variant: .danger, role: .defaultAction, isEnabled: isEnabled, help: help, action: action)
    }

    /// The button that dismisses the sheet, bound to Escape.
    public static func cancel(_ label: String = "Cancel", action: @escaping () -> Void) -> DKSheetAction {
        DKSheetAction(label, role: .cancel, action: action)
    }

    /// The key each action answers, in order. Return goes to the first action
    /// whose role is `defaultAction`, or, when there is none, to the first
    /// `automatic` action that looks `primary`. Escape goes to the first
    /// `cancel` action. Every other action gets nil, so no key is bound twice.
    public static func shortcuts(for actions: [DKSheetAction]) -> [DKSheetShortcut?] {
        let defaultIndex = actions.firstIndex { $0.role == .defaultAction }
            ?? actions.firstIndex { $0.role == .automatic && $0.spec.variant == .primary }
        let cancelIndex = actions.firstIndex { $0.role == .cancel }
        return actions.indices.map { index in
            if index == defaultIndex {
                return .defaultAction
            }
            if index == cancelIndex {
                return .cancelAction
            }
            return nil
        }
    }
}

// MARK: - Sheet

/// The frame every Launchpad sheet shares: a title, an optional subtitle, an
/// optional pages control centered under them, the scrolling body, and a footer
/// of leading buttons, an accessory, a note and the trailing buttons.
///
/// The body stacks its views 16pt apart. The sheet is as tall as its content
/// up to `maxHeight`, past which the body scrolls, so a paged sheet resizes to
/// each page as a settings window does. The pages control is a slot; put the
/// segmented control there and switch the body on its selection.
///
/// The primary button answers Return and the cancel button answers Escape; see
/// `DKSheetAction.shortcuts(for:)`.
public struct DKSheet<Pages: View, Content: View, Accessory: View>: View {
    public var title: String
    public var subtitle: String?
    /// The sheet's width; nil leaves it to the content.
    public var width: CGFloat?
    /// The tallest the sheet grows before the body scrolls.
    public var maxHeight: CGFloat
    public var note: DKSheetNote?
    public var leading: [DKSheetAction]
    public var trailing: [DKSheetAction]
    let pages: Pages
    let content: Content
    let accessory: Accessory

    @State private var headHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    public init(
        _ title: String,
        subtitle: String? = nil,
        width: CGFloat? = DKSheetMetrics.defaultWidth,
        maxHeight: CGFloat = DKSheetMetrics.defaultMaxHeight,
        note: DKSheetNote? = nil,
        leading: [DKSheetAction] = [],
        trailing: [DKSheetAction] = [],
        @ViewBuilder content: () -> Content,
        @ViewBuilder pages: () -> Pages,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.maxHeight = maxHeight
        self.note = note
        self.leading = leading
        self.trailing = trailing
        self.content = content()
        self.pages = pages()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            head
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DK.Space.s1)
                .padding(.horizontal, DKSheetMetrics.horizontalPadding)
                .padding(.bottom, DK.Space.s4)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: DKSheetMetrics.bodyHeight(
                content: contentHeight,
                chrome: headHeight + footerHeight,
                maxHeight: maxHeight,
            ))
            if hasFooter {
                footer
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
            }
        }
        .frame(width: width)
        .background(DK.Palette.window)
        .foregroundStyle(DK.Palette.ink)
        .font(DK.Typeface.body)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    // MARK: - Parts

    private var head: some View {
        VStack(spacing: DK.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DK.Typeface.sheetTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(DK.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if Pages.self != EmptyView.self {
                pages
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, DKSheetMetrics.horizontalPadding)
        .padding(.bottom, DK.Space.s3)
    }

    private var hasFooter: Bool {
        !leading.isEmpty || !trailing.isEmpty || note != nil || Accessory.self != EmptyView.self
    }

    private var footer: some View {
        let shortcuts = DKSheetAction.shortcuts(for: leading + trailing)
        let leadingShortcuts = Array(shortcuts.prefix(leading.count))
        let trailingShortcuts = Array(shortcuts.dropFirst(leading.count))
        return HStack(spacing: DK.Space.s2) {
            buttons(leading, leadingShortcuts)
            accessory
            if let note, !note.text.isEmpty {
                Text(note.text)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(note.tone.color)
                    .lineLimit(2)
            }
            Spacer(minLength: DK.Space.s4)
            buttons(trailing, trailingShortcuts)
        }
        .padding(.horizontal, DKSheetMetrics.horizontalPadding)
        .padding(.vertical, DK.Space.s3)
        .overlay(alignment: .top) {
            DKChromeRule(axis: .horizontal)
        }
    }

    private func buttons(_ actions: [DKSheetAction], _ shortcuts: [DKSheetShortcut?]) -> some View {
        ForEach(Array(zip(actions, shortcuts)), id: \.0.id) { action, shortcut in
            if let shortcut {
                DKButton(action.spec).keyboardShortcut(shortcut.keyboardShortcut)
            } else {
                DKButton(action.spec)
            }
        }
    }
}

public extension DKSheet where Pages == EmptyView, Accessory == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        width: CGFloat? = DKSheetMetrics.defaultWidth,
        maxHeight: CGFloat = DKSheetMetrics.defaultMaxHeight,
        note: DKSheetNote? = nil,
        leading: [DKSheetAction] = [],
        trailing: [DKSheetAction] = [],
        @ViewBuilder content: () -> Content,
    ) {
        self.init(
            title, subtitle: subtitle, width: width, maxHeight: maxHeight, note: note,
            leading: leading, trailing: trailing,
            content: content, pages: { EmptyView() }, accessory: { EmptyView() },
        )
    }
}

public extension DKSheet where Accessory == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        width: CGFloat? = DKSheetMetrics.defaultWidth,
        maxHeight: CGFloat = DKSheetMetrics.defaultMaxHeight,
        note: DKSheetNote? = nil,
        leading: [DKSheetAction] = [],
        trailing: [DKSheetAction] = [],
        @ViewBuilder content: () -> Content,
        @ViewBuilder pages: () -> Pages,
    ) {
        self.init(
            title, subtitle: subtitle, width: width, maxHeight: maxHeight, note: note,
            leading: leading, trailing: trailing,
            content: content, pages: pages, accessory: { EmptyView() },
        )
    }
}

public extension DKSheet where Pages == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        width: CGFloat? = DKSheetMetrics.defaultWidth,
        maxHeight: CGFloat = DKSheetMetrics.defaultMaxHeight,
        note: DKSheetNote? = nil,
        leading: [DKSheetAction] = [],
        trailing: [DKSheetAction] = [],
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.init(
            title, subtitle: subtitle, width: width, maxHeight: maxHeight, note: note,
            leading: leading, trailing: trailing,
            content: content, pages: { EmptyView() }, accessory: accessory,
        )
    }
}

// MARK: - Metrics

/// A sheet's fixed measures.
public enum DKSheetMetrics {
    /// The New Machine sheet's width; Machine Settings uses 640, wide sheets 720.
    public static let defaultWidth: CGFloat = 680
    /// The tallest a sheet grows before its body scrolls.
    public static let defaultMaxHeight: CGFloat = 800
    /// The inset of the head, the body and the footer from the sheet's sides.
    public static let horizontalPadding: CGFloat = 22

    /// The body's height: all of its content when the sheet fits under
    /// `maxHeight`, otherwise what is left after the head and footer.
    public static func bodyHeight(content: CGFloat, chrome: CGFloat, maxHeight: CGFloat) -> CGFloat {
        max(0, min(content, maxHeight - chrome))
    }
}
