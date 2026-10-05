import SwiftUI

/// The icon names the design uses, each drawn with an SF Symbol. Components take
/// a `DKGlyph`, never a raw symbol name, so the set stays the design's.
public enum DKGlyph: String, Sendable, CaseIterable, Hashable {
    case phone, ipad, machines, image, disk, drive, bundle, network, terminal, checklist
    case info, sliders, apps, cpu, gear, folder, folderPlus, pencil, key, list, clipboard
    case warning, check, play, stop, pause, restart, plus, minus, sun
    case speakerPlus, speakerMinus, mute, search, refresh, trash, copy, download, upload
    case left, right, sidebar, home, camera, record, ellipsis, timer, bolt, xCircle
    case send, link, doc, globe, seal, lock, chevron, chevronDown, close, pending, spinner

    /// The SF Symbol that draws this glyph.
    public var symbolName: String {
        switch self {
        case .phone: "iphone"
        case .ipad: "ipad"
        case .machines: "rectangle.stack"
        case .image: "opticaldisc"
        case .disk: "externaldrive"
        case .drive: "internaldrive"
        case .bundle: "shippingbox"
        case .network: "network"
        case .terminal: "terminal"
        case .checklist: "checklist"
        case .info: "info.circle"
        case .sliders: "slider.horizontal.3"
        case .apps: "square.grid.2x2"
        case .cpu: "cpu"
        case .gear: "gearshape"
        case .folder: "folder"
        case .folderPlus: "folder.badge.plus"
        case .pencil: "pencil"
        case .key: "key"
        case .list: "list.bullet"
        case .clipboard: "doc.on.clipboard"
        case .warning: "exclamationmark.triangle.fill"
        case .check: "checkmark.circle.fill"
        case .play: "play.fill"
        case .stop: "stop.fill"
        case .pause: "pause.fill"
        case .restart: "arrow.counterclockwise"
        case .plus: "plus"
        case .minus: "minus"
        case .sun: "sun.max"
        case .speakerPlus: "speaker.plus"
        case .speakerMinus: "speaker.minus"
        case .mute: "speaker.slash"
        case .search: "magnifyingglass"
        case .refresh: "arrow.clockwise"
        case .trash: "trash"
        case .copy: "doc.on.doc"
        case .download: "arrow.down.circle"
        case .upload: "arrow.up.circle"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .sidebar: "sidebar.trailing"
        case .home: "circle.circle"
        case .camera: "camera"
        case .record: "record.circle"
        case .ellipsis: "ellipsis"
        case .timer: "timer"
        case .bolt: "bolt"
        case .xCircle: "xmark.circle.fill"
        case .send: "paperplane"
        case .link: "link"
        case .doc: "doc"
        case .globe: "globe"
        case .seal: "checkmark.seal"
        case .lock: "lock"
        case .chevron: "chevron.right"
        case .chevronDown: "chevron.down"
        case .close: "xmark"
        case .pending: "circle.dotted"
        case .spinner: "progress.indicator"
        }
    }
}

/// A design glyph at a point size.
public struct DKIcon: View {
    public let glyph: DKGlyph
    public var size: CGFloat

    public init(_ glyph: DKGlyph, size: CGFloat = 15) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        Image(systemName: glyph.symbolName)
            .font(.system(size: size * 0.86, weight: .regular))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
