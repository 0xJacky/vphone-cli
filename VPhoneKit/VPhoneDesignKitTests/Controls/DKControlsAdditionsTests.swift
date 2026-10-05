import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The native search field, focus-out on outside clicks, menu buttons and capped lists.
@MainActor
@Suite("DesignKit control additions")
struct DKControlsAdditionsTests {
    private func host(_ view: some View) -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (window, host)
    }

    private func searchField(in view: NSView) -> DKSearchFieldView? {
        if let field = view as? DKSearchFieldView {
            return field
        }
        for subview in view.subviews {
            if let field = searchField(in: subview) {
                return field
            }
        }
        return nil
    }

    @Test
    func `the search field is a real NSSearchField that AppKit can find`() throws {
        let (window, host) = host(DKSearchField("Search machines", text: .constant("research")))
        defer { window.contentView = nil }
        let field = try #require(searchField(in: host))
        #expect(field.isKind(of: NSSearchField.self))
        #expect(field.stringValue == "research")
        #expect(field.placeholderAttributedString?.string == "Search machines")
    }

    /// Waits up to two seconds for `condition`, letting the main queue run.
    /// Other tests may hold the main actor for a while, so a fixed wait is flaky.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 100 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Async, so the main queue can run the deferred focus change between steps;
    /// a nested run loop inside a main-queue job would not.
    @Test
    func `binding the focus to true makes the field first responder`() async throws {
        final class Box {
            var focused = true
        }
        let box = Box()
        let binding = Binding(get: { box.focused }, set: { box.focused = $0 })
        let (window, host) = host(DKSearchField("Search", text: .constant(""), isFocused: binding))
        defer { window.contentView = nil }
        let field = try #require(searchField(in: host))
        #expect(await eventually { field.hasKeyboardFocus })
        window.makeFirstResponder(nil)
        #expect(await eventually { !box.focused })
        window.makeFirstResponder(field)
        #expect(await eventually { box.focused })
    }

    @Test
    func `only a click outside the input in its own window ends editing`() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let frame = NSRect(x: 10, y: 10, width: 100, height: 28)
        #expect(DKInputFocusDismissal.shouldDismissFocus(eventWindow: window, inputWindow: window, location: NSPoint(x: 200, y: 200), inputFrame: frame))
        #expect(!DKInputFocusDismissal.shouldDismissFocus(eventWindow: window, inputWindow: window, location: NSPoint(x: 20, y: 20), inputFrame: frame))
        #expect(!DKInputFocusDismissal.shouldDismissFocus(eventWindow: other, inputWindow: window, location: NSPoint(x: 200, y: 200), inputFrame: frame))
        #expect(!DKInputFocusDismissal.shouldDismissFocus(eventWindow: nil, inputWindow: window, location: NSPoint(x: 200, y: 200), inputFrame: frame))
    }

    @Test
    func `a menu button's menu holds its rows`() {
        let menu = DKMenuButton.makeMenu([
            DKMenuItem("Terminate") {},
            DKMenuItem.separator,
            DKMenuItem("Kill") {}.destructive(),
        ], title: "Signal")
        #expect(menu.title == "Signal")
        #expect(menu.items.map(\.title) == ["Terminate", "", "Kill"])
        #expect(menu.items[1].isSeparatorItem)
    }

    @Test
    func `a disabled menu button's anchor lets clicks through`() {
        let anchor = DKMenuButtonAnchorView(frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        let container = NSView(frame: anchor.frame)
        container.addSubview(anchor)
        #expect(anchor.hitTest(NSPoint(x: 10, y: 10)) === anchor)
        anchor.isEnabled = false
        #expect(anchor.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test
    func `a capped list is as tall as its content up to the cap`() {
        #expect(DKCappedScrollMath.height(content: 120, cap: 360) == 120)
        #expect(DKCappedScrollMath.height(content: 900, cap: 360) == 360)
        #expect(DKCappedScrollMath.cap(maxHeight: 360, screen: 800) == 360)
        #expect(DKCappedScrollMath.cap(maxHeight: 360, screen: 200) == 200)
        #expect(DKCappedScrollMath.cap(maxHeight: nil, screen: 700) == 700)
        #expect(DKCappedScrollMath.cap(maxHeight: 10, screen: 700) == DKCappedScrollMath.minimumHeight)
        #expect(DKCappedScroll.defaultMaxHeight == 360)
        #expect(DKCappedScroll.screenCap() >= DKCappedScrollMath.minimumHeight)
    }
}
