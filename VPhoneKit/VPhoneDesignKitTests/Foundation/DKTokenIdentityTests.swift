import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Color tokens are cached instances. A SwiftUI `Color` made from an `NSColor`
/// equals only a color made from the same `NSColor` instance, so a token built
/// afresh on every read would make every view that stores it differ from its
/// previous value and defeat SwiftUI's skipping of unchanged subtrees.
@Suite("DesignKit token identity")
struct DKTokenIdentityTests {
    private static let tokens: [(String, @Sendable () -> Color)] = [
        ("accent", { DK.Palette.accent }),
        ("accentPressed", { DK.Palette.accentPressed }),
        ("successLine", { DK.Palette.successLine }),
        ("onAccentMuted", { DK.Palette.onAccentMuted }),
        ("onAccentTint", { DK.Palette.onAccentTint }),
    ]

    @Test
    func `every token reads as the same color twice`() {
        for (name, read) in Self.tokens {
            #expect(read() == read(), "DK.Palette.\(name) built a new color on read")
        }
    }

    @Test
    func `every tone color reads as the same color twice`() {
        for tone in DKTone.allCases {
            #expect(tone.color == tone.color, "\(tone).color")
            #expect(tone.ink == tone.ink, "\(tone).ink")
            #expect(tone.surface == tone.surface, "\(tone).surface")
            #expect(tone.line == tone.line, "\(tone).line")
            #expect(tone.text == tone.text, "\(tone).text")
        }
    }

    @Test
    func `two separately built dynamic colors are not equal, so the checks above can fail`() {
        #expect(DK.Palette.dynamic(0x000000, 0xFFFFFF) != DK.Palette.dynamic(0x000000, 0xFFFFFF))
    }

    @Test
    func `a dynamic color takes its dark value in Vibrant Dark, as menus and popovers draw`() throws {
        let color = DK.Palette.dynamicNSColor(0xFFFFFF, 0x000000)
        let vibrant = try #require(NSAppearance(named: .vibrantDark))
        #expect(vibrant.name != .darkAqua)
        var resolved: NSColor?
        vibrant.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        #expect(try #require(resolved).redComponent < 0.01)
    }

    @Test
    func `the success line is the success color at 35 percent`() throws {
        var light: NSColor?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            light = NSColor(DK.Palette.successLine).usingColorSpace(.sRGB)
        }
        let color = try #require(light)
        #expect(abs(color.alphaComponent - 0.35) < 0.01)
        #expect(Int((color.greenComponent * 255).rounded()) == 0xB4)
    }
}
