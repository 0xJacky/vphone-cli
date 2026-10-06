import AppKit
import Testing
@testable import VPhoneDesignKit

/// The window buttons a content-drawn title bar puts in place of the system's.
@Suite("DesignKit window controls")
struct DKWindowControlsTests {
    private let standard: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

    @Test
    func `the buttons match the system's size and spacing`() {
        #expect(DKWindowControlsMetrics.diameter == 14)
        #expect(DKWindowControlsMetrics.gap == 9)
        #expect(DKWindowControls.width == 60)
    }

    @Test
    func `the buttons run close, minimize, zoom`() {
        #expect(DKWindowButton.allCases == [.close, .minimize, .zoom])
    }

    @Test
    func `each button shows its symbol, and Option turns zoom into a plus`() {
        #expect(DKWindowButton.symbolName(.close, option: false) == "xmark")
        #expect(DKWindowButton.symbolName(.minimize, option: true) == "minus")
        #expect(DKWindowButton.symbolName(.zoom, option: false) == "arrow.up.left.and.arrow.down.right")
        #expect(DKWindowButton.symbolName(.zoom, option: true) == "plus")
        for button in DKWindowButton.allCases {
            for option in [false, true] {
                #expect(NSImage(systemSymbolName: DKWindowButton.symbolName(button, option: option), accessibilityDescription: nil) != nil)
            }
        }
    }

    @Test
    func `zoom enters full screen unless Option is down or the window cannot`() {
        #expect(DKWindowButton.zoomTogglesFullScreen(option: false, behavior: [], styleMask: standard))
        #expect(DKWindowButton.zoomTogglesFullScreen(option: false, behavior: .fullScreenPrimary, styleMask: standard))
        #expect(!DKWindowButton.zoomTogglesFullScreen(option: true, behavior: [], styleMask: standard))
        #expect(!DKWindowButton.zoomTogglesFullScreen(option: false, behavior: .fullScreenNone, styleMask: standard))
        #expect(!DKWindowButton.zoomTogglesFullScreen(option: false, behavior: .fullScreenAuxiliary, styleMask: standard))
        #expect(!DKWindowButton.zoomTogglesFullScreen(option: false, behavior: [], styleMask: [.titled, .closable]))
    }

    @Test
    func `a button is offered only when the window's style has it`() {
        for button in DKWindowButton.allCases {
            #expect(DKWindowButton.isAvailable(button, styleMask: standard))
            #expect(!DKWindowButton.isAvailable(button, styleMask: [.titled]))
        }
    }

    @Test
    func `the names fall back to English without a catalog`() {
        #expect(DKWindowButton.allCases.map { $0.title(bundle: .main) } == ["Close", "Minimize", "Full Screen"])
    }
}
