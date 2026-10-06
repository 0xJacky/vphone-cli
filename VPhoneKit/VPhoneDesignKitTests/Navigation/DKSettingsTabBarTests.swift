import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The settings window's header band and the window buttons it carries.
@Suite("DesignKit settings tab bar")
@MainActor
struct DKSettingsTabBarTests {
    private let tabs = [
        DKSettingsTab(id: "general", title: "General", glyph: .gear),
        DKSettingsTab(id: "library", title: "Library", glyph: .folder),
        DKSettingsTab(id: "advanced", title: "Advanced", glyph: .sliders),
    ]

    @Test
    func `the title is the selected tab's name`() {
        #expect(tabs.settingsTitle(for: "general") == "General")
        #expect(tabs.settingsTitle(for: "advanced") == "Advanced")
        #expect(tabs.settingsTitle(for: "missing") == "")
    }

    @Test
    func `the selected tab is accent ink on the accent tint`() {
        #expect(DKSettingsTabBarMetrics.ink(isSelected: true) == DK.Palette.accent)
        #expect(DKSettingsTabBarMetrics.ground(isSelected: true, isHovered: false) == DK.Palette.accentTint)
        #expect(DKSettingsTabBarMetrics.ground(isSelected: true, isHovered: true) == DK.Palette.accentTint)
    }

    @Test
    func `other tabs are secondary ink, tinted only under the pointer`() {
        #expect(DKSettingsTabBarMetrics.ink(isSelected: false) == DK.Palette.inkSecondary)
        #expect(DKSettingsTabBarMetrics.ground(isSelected: false, isHovered: false) == .clear)
        #expect(DKSettingsTabBarMetrics.ground(isSelected: false, isHovered: true) == DK.Palette.selectionNeutral)
    }

    @Test
    func `the band follows the design's measures`() {
        #expect(DKSettingsTabBarMetrics.tabMinWidth == 72)
        #expect(DKSettingsTabBarMetrics.glyphSize == 22)
        #expect(DKSettingsTabBarMetrics.tabRadius == 8)
        // Title row: 10pt in from the top, 18pt tall, so its middle is 19pt down.
        #expect(DKSettingsTabBarMetrics.topPadding + DKSettingsTabBarMetrics.titleHeight / 2 == 19)
        // The window buttons sit level with it, 20pt in and down to their centers.
        #expect(DKSettingsTabBarMetrics.windowControlsTop + DKWindowControlsMetrics.diameter / 2 == 20)
        #expect(DKSettingsTabBarMetrics.windowControlsLeading + DKWindowControlsMetrics.diameter / 2 == 20)
    }

    @Test
    func `a page header's window buttons line up with a sidebar's`() {
        // Centered 22pt below the window's top, as in DKSidebar's window band.
        #expect(DK.Space.s3 + DKPageHeaderMetrics.windowControlsTop + DKWindowControlsMetrics.diameter / 2 == 22)
    }

    @Test
    func `a window offers only the buttons its style has`() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(DKWindowButton.offered(in: window) == [.close])

        let full = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true,
        )
        full.isReleasedWhenClosed = false
        #expect(DKWindowButton.offered(in: full) == Set(DKWindowButton.allCases))

        full.standardWindowButton(.zoomButton)?.isEnabled = false
        #expect(DKWindowButton.offered(in: full) == [.close, .minimize])
    }
}
