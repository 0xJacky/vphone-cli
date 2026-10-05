import AppKit
import SwiftUI

/// The DesignKit namespace: tokens shared by every component, ported from the
/// design canvas's `designkit.css`. Light values come first, dark values second;
/// each color follows the view's appearance.
public enum DK {}

// MARK: - Color

public extension DK {
    /// Semantic colors. Each resolves against the current appearance, so a view
    /// inside a dark window gets the dark value without being told.
    enum Palette {
        // MARK: Grounds

        /// The ground behind windows, sheets and standalone panels.
        public static let page = dynamic(0xF5F5F7, 0x101012)
        /// A window's content background.
        public static let window = dynamic(0xFFFFFF, 0x1C1C1E)
        /// Sidebars and sheet chrome.
        public static let sidebar = dynamic(0xF9F9FB, 0x232326)
        /// Cards and grouped rows.
        public static let surfaceRaised = dynamic(0xFCFCFD, 0x26262A)
        /// Wells: search fields, path chips, segmented tracks.
        public static let surfaceSunken = dynamic(0xEFEFF2, 0x2A2A2D)
        /// The selected segment's fill.
        public static let segmentSelected = dynamic(0xFFFFFF, 0x48484D)

        // MARK: Lines

        public static let line = dynamic(0xEBEBEE, 0x333336)
        public static let lineStrong = dynamic(0xDDDDE2, 0x3A3A3E)
        public static let divider = dynamic(0xECECEF, 0x2E2E31)
        public static let dividerSoft = dynamic(0xF1F1F3, 0x2C2C2F)
        public static let track = dynamic(0xECECEF, 0x3A3A3E)

        // MARK: Ink

        public static let ink = dynamic(0x1D1D1F, 0xF2F2F4)
        public static let inkSecondary = dynamic(0x3C3C43, 0xD8D8DC)
        public static let muted = dynamic(0x6E6E73, 0xA8A8AD)
        public static let inkDisabled = dynamic(0xA6A6AC, 0x5A5A5F)

        // MARK: Accent

        public static let accent = dynamic(0x007AFF, 0x0A84FF)
        public static let accentSoft = dynamic(0x8EC5FF, 0x3A6EA8)
        public static let accentTint = dynamic(0x007AFF, 0x0A84FF, lightAlpha: 0.12, darkAlpha: 0.24)
        public static let onAccent = dynamic(0xFFFFFF, 0xFFFFFF)
        public static let link = dynamic(0x0071E3, 0x4EA1FF)
        public static let selectionNeutral = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.10)

        // MARK: Status

        public static let success = dynamic(0x28B44A, 0x30D158)
        public static let successInk = dynamic(0x1A7F37, 0x5FE08A)
        public static let successSurface = dynamic(0x30D158, 0x30D158, lightAlpha: 0.14, darkAlpha: 0.18)
        public static let warning = dynamic(0xE0A000, 0xFFD60A)
        public static let warningInk = dynamic(0x8A6100, 0xFFE066)
        public static let warningSurface = dynamic(0xFFF8E1, 0x2B2714)
        public static let warningLine = dynamic(0xF0D48A, 0x6B5A12)
        public static let danger = dynamic(0xC4281C, 0xFF6961)
        public static let dangerSurface = dynamic(0xFFF1F0, 0x2F1F1E)
        public static let dangerLine = dynamic(0xF3C4BF, 0x5C2A27)
        public static let dotIdle = dynamic(0x8E8E93, 0x8E8E93)

        // MARK: Guest display and terminal

        /// Behind the guest's screen.
        public static let display = dynamic(0x000000, 0x000000)
        public static let terminalBackground = dynamic(0xFEFFFF, 0x1E1E1E)
        public static let terminalForeground = dynamic(0x000000, 0xFFFFFF)
        public static let terminalDim = dynamic(0x464646, 0x98989D)
        public static let terminalBlue = dynamic(0x0869CB, 0x0A84FF)
        public static let terminalGreen = dynamic(0x26A439, 0x32D74B)
        public static let terminalRed = dynamic(0xCC372E, 0xFF453A)

        // MARK: File icons

        public static let folderBack = dynamic(0x2B86E6, 0x5B8FD6)
        public static let folderFront = dynamic(0x4CA7F8, 0x79A9E8)
        public static let folderArrow = dynamic(0xFFFFFF, 0x0E2742)
        public static let docPaper = dynamic(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.09)
        public static let docLine = dynamic(0xC9C7C4, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.26)
        public static let docFold = dynamic(0xEEEDEA, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.16)
        public static let docDetail = dynamic(0xA8A6A3, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.32)
        public static let iconTeal = dynamic(0x0FB6AC, 0x2DD4BF)
        public static let tagInk = dynamic(0x0C1320, 0x0C1320)
        public static let tagBlue = dynamic(0x8AB3F7, 0x8AB3F7)
        public static let tagPython = dynamic(0x5C9CD6, 0x5C9CD6)
        public static let tagGo = dynamic(0x4DC4D6, 0x4DC4D6)
        public static let tagYAML = dynamic(0xC98CDB, 0xC98CDB)
        public static let tagArchive = dynamic(0xE0A359, 0xE0A359)

        /// A color with a light and a dark value, resolved by the appearance it is drawn in.
        public static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
            })
        }
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha,
        )
    }
}

// MARK: - Metrics

public extension DK {
    /// The 4pt spacing scale. `s2` is the base unit.
    enum Space {
        public static let s1: CGFloat = 4
        public static let s2: CGFloat = 8
        public static let s3: CGFloat = 12
        public static let s4: CGFloat = 16
        public static let s5: CGFloat = 20
        public static let s6: CGFloat = 24
        public static let s8: CGFloat = 32
    }

    enum Radius {
        public static let menuItem: CGFloat = 5
        public static let field: CGFloat = 6
        public static let row: CGFloat = 7
        public static let control: CGFloat = 8
        public static let card: CGFloat = 10
        public static let window: CGFloat = 12
        public static let sheet: CGFloat = 14
    }

    enum Metric {
        public static let controlHeight: CGFloat = 30
        public static let controlHeightSmall: CGFloat = 24
        public static let rowHeight: CGFloat = 32
        public static let tableRowHeight: CGFloat = 30
        /// Two-line table rows (a title over a monospaced subtitle).
        public static let tableRowHeightRoomy: CGFloat = 58
        public static let statusBarHeight: CGFloat = 26
        public static let sidebarWidth: CGFloat = 232
        public static let dot: CGFloat = 8
        public static let hairline: CGFloat = 1
    }
}

// MARK: - Type

public extension DK {
    /// System text for UI; monospace only for command text, identifiers and logs.
    enum Typeface {
        public static let body = Font.system(size: 13)
        public static let bodyStrong = Font.system(size: 13, weight: .semibold)
        public static let caption = Font.system(size: 12)
        public static let captionStrong = Font.system(size: 12, weight: .semibold)
        public static let footnote = Font.system(size: 11)
        public static let sectionTitle = Font.system(size: 12, weight: .semibold)
        public static let pageTitle = Font.system(size: 15, weight: .bold)
        public static let sheetTitle = Font.system(size: 17, weight: .semibold)
        public static let mono = Font.system(size: 12, design: .monospaced)
        public static let monoSmall = Font.system(size: 11, design: .monospaced)
        public static let log = Font.system(size: 12, design: .monospaced)
    }
}
