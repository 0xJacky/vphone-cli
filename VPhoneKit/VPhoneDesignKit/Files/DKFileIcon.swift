import SwiftUI

/// A file-type icon drawn from paths, after uTerm's `SFTPFileIcon`: a two-tone
/// folder (with an up arrow for "..", a link arrow for a linked folder), or a
/// page with a folded corner carrying a colored type tag, detail lines, or a
/// link arrow for a symbolic link.
///
/// The drawing is laid out on a 24-unit canvas and scaled to `size`, strokes
/// included. 16 is the list size; inspectors use 48.
public struct DKFileIcon: View {
    public let kind: DKFileKind
    public var size: CGFloat

    public init(_ kind: DKFileKind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    /// An icon for a directory entry, classified with `DKFileKind(name:isDirectory:isSymlink:)`.
    public init(name: String, isDirectory: Bool = false, isSymlink: Bool = false, size: CGFloat = 16) {
        self.init(DKFileKind(name: name, isDirectory: isDirectory, isSymlink: isSymlink), size: size)
    }

    public var body: some View {
        ZStack {
            switch kind {
            case .folder:
                folder
            case .parent:
                folder
                part(.parentArrow).stroke(DK.Palette.folderArrow, style: stroke(1.7, cap: .round))
            case .folderSymlink:
                folder
                part(.linkArrow).stroke(DK.Palette.folderArrow, style: stroke(1.6, cap: .round))
            case .symlink:
                document
                part(.linkArrow).stroke(DK.Palette.iconTeal, style: stroke(1.6, cap: .round))
            case let .document(tag):
                document
                if let tag {
                    tagLabel(tag)
                } else {
                    part(.detailLines).stroke(DK.Palette.docDetail, style: stroke(1.2, cap: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Pieces

    private var folder: some View {
        ZStack {
            part(.folderBack).fill(DK.Palette.folderBack)
            part(.folderFront).fill(DK.Palette.folderFront)
        }
    }

    private var document: some View {
        ZStack {
            part(.paper).fill(DK.Palette.docPaper)
            part(.paper).stroke(DK.Palette.docLine, style: stroke(1.1))
            part(.fold).fill(DK.Palette.docFold)
            part(.fold).stroke(DK.Palette.docLine, style: stroke(1.1))
        }
    }

    /// The design's tag: a 12 x 6.2 rounded label centered at (12, 15.5), its
    /// text 5 units tall, or 3.8 for four letters.
    private func tagLabel(_ tag: DKFileTag) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: units(1.4), style: .continuous)
                .fill(tag.color)
                .frame(width: units(12), height: units(6.2))
            Text(tag.text)
                .font(.system(size: units(tag.isCompact ? 3.8 : 5), weight: .bold, design: .monospaced))
                .foregroundStyle(DK.Palette.tagInk)
                .lineLimit(1)
                .fixedSize()
        }
        .position(x: units(12), y: units(15.5))
    }

    private func part(_ part: DKFileIconPart) -> DKFileIconShape {
        DKFileIconShape(part: part)
    }

    private func units(_ value: CGFloat) -> CGFloat {
        value * size / DKFileIconPart.canvas
    }

    private func stroke(_ width: CGFloat, cap: CGLineCap = .butt) -> StrokeStyle {
        StrokeStyle(lineWidth: units(width), lineCap: cap, lineJoin: .round)
    }
}

// MARK: - Geometry

/// The icon's paths on the 24-unit canvas, point for point from uTerm's
/// `SFTPFileIcon` and the design's `DKFileIcon`.
enum DKFileIconPart: Hashable, Sendable {
    case folderBack, folderFront, parentArrow, linkArrow, paper, fold, detailLines

    static let canvas: CGFloat = 24

    var unitPath: Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x, y: y)
        }
        switch self {
        case .folderBack:
            path.move(to: p(2.5, 7.4))
            path.addQuadCurve(to: p(4.05, 5.85), control: p(2.5, 5.85))
            path.addLine(to: p(8.95, 5.85))
            path.addLine(to: p(10.85, 7.9))
            path.addLine(to: p(20.45, 7.9))
            path.addQuadCurve(to: p(22, 9.45), control: p(22, 7.9))
            path.addLine(to: p(22, 18.15))
            path.addQuadCurve(to: p(20.45, 19.7), control: p(22, 19.7))
            path.addLine(to: p(4.05, 19.7))
            path.addQuadCurve(to: p(2.5, 18.15), control: p(2.5, 19.7))
            path.closeSubpath()
        case .folderFront:
            path.move(to: p(2.5, 10.7))
            path.addLine(to: p(21.55, 10.7))
            path.addLine(to: p(21.55, 18.15))
            path.addQuadCurve(to: p(20, 19.7), control: p(21.55, 19.7))
            path.addLine(to: p(4.05, 19.7))
            path.addQuadCurve(to: p(2.5, 18.15), control: p(2.5, 19.7))
            path.closeSubpath()
        case .parentArrow:
            path.move(to: p(12, 17.6))
            path.addLine(to: p(12, 13.5))
            path.move(to: p(9.7, 15.4))
            path.addLine(to: p(12, 13.1))
            path.addLine(to: p(14.3, 15.4))
        case .linkArrow:
            path.move(to: p(9, 18.3))
            path.addLine(to: p(9, 16.1))
            path.addQuadCurve(to: p(10.7, 14.4), control: p(9, 14.4))
            path.addLine(to: p(13.3, 14.4))
            path.move(to: p(11.6, 12.6))
            path.addLine(to: p(14.2, 14.4))
            path.addLine(to: p(11.6, 16.2))
        case .paper:
            path.move(to: p(6.4, 3))
            path.addLine(to: p(12.7, 3))
            path.addLine(to: p(18, 8.2))
            path.addLine(to: p(18, 20))
            path.addQuadCurve(to: p(17, 21), control: p(18, 21))
            path.addLine(to: p(6.4, 21))
            path.addQuadCurve(to: p(5.4, 20), control: p(5.4, 21))
            path.addLine(to: p(5.4, 4))
            path.addQuadCurve(to: p(6.4, 3), control: p(5.4, 3))
            path.closeSubpath()
        case .fold:
            path.move(to: p(12.6, 3.05))
            path.addLine(to: p(12.6, 7.2))
            path.addQuadCurve(to: p(13.6, 8.2), control: p(12.6, 8.2))
            path.addLine(to: p(17.8, 8.2))
            path.closeSubpath()
        case .detailLines:
            path.move(to: p(8.2, 12.6))
            path.addLine(to: p(15.8, 12.6))
            path.move(to: p(8.2, 15.1))
            path.addLine(to: p(15.8, 15.1))
            path.move(to: p(8.2, 17.6))
            path.addLine(to: p(12.8, 17.6))
        }
        return path
    }
}

/// One icon part scaled from the 24-unit canvas into the frame it is given.
struct DKFileIconShape: Shape {
    let part: DKFileIconPart

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / DKFileIconPart.canvas
        return part.unitPath.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale),
        )
    }
}

// MARK: - Preview

#Preview("File icons") {
    DKFileIconGallery()
        .padding(DK.Space.s4)
        .background(DK.Palette.window)
        .preferredColorScheme(.light)
}

#Preview("File icons, dark") {
    DKFileIconGallery()
        .padding(DK.Space.s4)
        .background(DK.Palette.window)
        .preferredColorScheme(.dark)
}

/// Every kind and every tag tone at 16 and 48pt.
private struct DKFileIconGallery: View {
    private let samples: [(String, DKFileKind)] = [
        ("..", .parent),
        ("Documents", .folder),
        ("Media", .folderSymlink),
        ("Downloads", .symlink),
        ("README", .document(nil)),
        ("notes.md", DKFileKind(name: "notes.md")),
        ("hook.py", DKFileKind(name: "hook.py")),
        ("main.go", DKFileKind(name: "main.go")),
        ("config.yaml", DKFileKind(name: "config.yaml")),
        ("Info.plist", DKFileKind(name: "Info.plist")),
        ("App.swift", DKFileKind(name: "App.swift")),
        ("run.sh", DKFileKind(name: "run.sh")),
        ("hook.c", DKFileKind(name: "hook.c")),
        ("backup.tar.gz", DKFileKind(name: "backup.tar.gz")),
        ("Demo.ipa", DKFileKind(name: "Demo.ipa")),
        ("shot.png", DKFileKind(name: "shot.png")),
        ("data.bin", DKFileKind(name: "data.bin")),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: DK.Space.s4), count: 6), spacing: DK.Space.s4) {
            ForEach(samples, id: \.0) { name, kind in
                VStack(spacing: 6) {
                    HStack(alignment: .bottom, spacing: DK.Space.s2) {
                        DKFileIcon(kind, size: 16)
                        DKFileIcon(kind, size: 48)
                    }
                    Text(name)
                        .font(DK.Typeface.monoSmall)
                        .foregroundStyle(DK.Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
