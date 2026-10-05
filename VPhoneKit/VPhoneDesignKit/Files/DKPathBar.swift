import SwiftUI

// MARK: - Component

/// One step of a path: its name and the full path up to and including it.
public struct DKPathComponent: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String

    public var id: String {
        path
    }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    /// The steps of a path, root excluded: "/var/mobile" gives "var" (/var)
    /// and "mobile" (/var/mobile). Repeated and trailing slashes are ignored. A
    /// relative path keeps its components relative: "a/b" gives "a" and "a/b".
    public static func components(of path: String) -> [DKPathComponent] {
        let isAbsolute = path.hasPrefix("/")
        var prefix: String? = isAbsolute ? "" : nil
        var result: [DKPathComponent] = []
        for name in path.split(separator: "/", omittingEmptySubsequences: true) {
            let full = prefix.map { "\($0)/\(name)" } ?? String(name)
            result.append(DKPathComponent(name: String(name), path: full))
            prefix = full
        }
        return result
    }
}

// MARK: - Path bar

/// The breadcrumb of a file browser: a root glyph, then each folder of the path
/// separated by "›", the current folder last as a chip. The root and every
/// folder but the current one are buttons that call `onSelect` with that
/// folder's full path ("/" for the root).
public struct DKPathBar: View {
    public let path: String
    public var rootGlyph: DKGlyph
    public var rootLabel: String
    public var onSelect: (String) -> Void

    public init(
        path: String,
        rootGlyph: DKGlyph = .drive,
        rootLabel: String = "Guest root",
        onSelect: @escaping (String) -> Void = { _ in },
    ) {
        self.path = path
        self.rootGlyph = rootGlyph
        self.rootLabel = rootLabel
        self.onSelect = onSelect
    }

    public var body: some View {
        let components = DKPathComponent.components(of: path)
        HStack(spacing: DK.Space.s1) {
            Button {
                onSelect("/")
            } label: {
                DKIcon(rootGlyph, size: 15)
            }
            .buttonStyle(DKPathBarCrumbStyle(isCurrent: components.isEmpty, isRoot: true))
            .help(rootLabel)
            .accessibilityLabel(rootLabel)

            ForEach(components.indices, id: \.self) { index in
                let component = components[index]
                let isCurrent = index == components.count - 1
                separator
                if isCurrent {
                    Text(component.name)
                        .modifier(DKPathBarCrumb(isCurrent: true, isPressed: false))
                        .layoutPriority(1)
                        .help(component.path)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button(component.name) {
                        onSelect(component.path)
                    }
                    .buttonStyle(DKPathBarCrumbStyle(isCurrent: false))
                    .help(component.path)
                }
            }
        }
        .foregroundStyle(DK.Palette.muted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }

    private var separator: some View {
        Text("›")
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.muted)
            .accessibilityHidden(true)
    }
}

// MARK: - Crumb styling

/// A folder name in the bar: secondary text with a hover well, the muted
/// root glyph, or the current folder's chip.
private struct DKPathBarCrumb: ViewModifier {
    let isCurrent: Bool
    let isPressed: Bool
    var isRoot = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .font(isCurrent ? .system(size: 13, weight: .medium) : DK.Typeface.body)
            .foregroundStyle(isCurrent ? DK.Palette.ink : isRoot ? DK.Palette.muted : DK.Palette.inkSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, DK.Space.s2)
            .padding(.vertical, DK.Space.s1)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.row, style: .continuous)
                    .fill(fill),
            )
            .contentShape(RoundedRectangle(cornerRadius: DK.Radius.row, style: .continuous))
            .onHover { isHovered = $0 && !isCurrent }
    }

    private var fill: Color {
        if isCurrent || isPressed {
            return DK.Palette.surfaceSunken
        }
        return isHovered ? DK.Palette.selectionNeutral : .clear
    }
}

private struct DKPathBarCrumbStyle: ButtonStyle {
    let isCurrent: Bool
    var isRoot = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(DKPathBarCrumb(isCurrent: isCurrent, isPressed: configuration.isPressed, isRoot: isRoot))
    }
}

// MARK: - Preview

#Preview("Path bar") {
    VStack(alignment: .leading, spacing: DK.Space.s3) {
        DKPathBar(path: "/var/mobile")
        DKPathBar(path: "/private/var/mobile/Containers/Data/Application")
        DKPathBar(path: "/")
    }
    .padding(DK.Space.s4)
    .frame(width: 520, alignment: .leading)
    .background(DK.Palette.window)
}

#Preview("Path bar, dark") {
    DKPathBar(path: "/var/mobile")
        .padding(DK.Space.s4)
        .background(DK.Palette.window)
        .preferredColorScheme(.dark)
}
