import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The tokens every component builds on.
@Suite("DesignKit foundation")
struct DKFoundationTests {
    @Test
    func `a dynamic color takes its light value in Aqua and its dark value in Dark Aqua`() throws {
        let color = NSColor(DK.Palette.dynamic(0x007AFF, 0x0A84FF))
        var light: NSColor?
        var dark: NSColor?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            light = color.usingColorSpace(.sRGB)
        }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            dark = color.usingColorSpace(.sRGB)
        }
        let l = try #require(light)
        let d = try #require(dark)
        #expect(Int((l.blueComponent * 255).rounded()) == 0xFF)
        #expect(Int((l.greenComponent * 255).rounded()) == 0x7A)
        #expect(Int((d.greenComponent * 255).rounded()) == 0x84)
    }

    @Test
    func `every glyph names an SF Symbol that exists`() {
        for glyph in DKGlyph.allCases {
            #expect(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil) != nil, "\(glyph)")
        }
    }

    @Test
    func `the spacing scale steps by four points`() {
        #expect([DK.Space.s1, DK.Space.s2, DK.Space.s3, DK.Space.s4, DK.Space.s5, DK.Space.s6] == [4, 8, 12, 16, 20, 24])
    }
}
