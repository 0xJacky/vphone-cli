import AppKit
import Testing
@testable import VPhoneDesignKit

/// The menu model, its layout, the NSMenu it builds, and the flat preview.
@MainActor
@Suite("DesignKit menus")
struct DKMenuTests {
    // MARK: - Builder and layout

    @Test
    func `the builder takes conditions and loops`() {
        let running = true
        let machines = ["research-26", "ipad-lab"]
        let menu = DKMenu("Menu bar icon") {
            DKMenuItem("Open Launchpad")
            if running {
                DKMenuItem("Stop")
            } else {
                DKMenuItem("Start")
            }
            DKMenuItem.separator
            for name in machines {
                DKMenuItem(name)
            }
        }
        #expect(menu.items.map(\.title) == ["Open Launchpad", "Stop", "", "research-26", "ipad-lab"])
        #expect(menu.items[2].kind == .separator)
    }

    @Test
    func `separators split sections and stray separators are dropped`() {
        let layout = DKMenuLayout([
            .separator,
            DKMenuItem("Open Launchpad"),
            .separator,
            .separator,
            .header("Running"),
            DKMenuItem("research-26"),
            .header("Stopped"),
            DKMenuItem("ios27-hooks"),
            .separator,
        ])
        #expect(layout.sections.count == 3)
        #expect(layout.sections.map(\.header) == [nil, "Running", "Stopped"])
        #expect(layout.sections.map(\.separatorBefore) == [false, true, false])
        #expect(layout.sections.map { $0.rows.map(\.item.title) } == [["Open Launchpad"], ["research-26"], ["ios27-hooks"]])
    }

    @Test
    func `an alternate pairs with the item before it and takes its shortcut plus Option`() throws {
        let layout = DKMenuLayout([
            DKMenuItem("Start", shortcut: "⌘R"),
            DKMenuItem("Start Headless").alternate(),
            DKMenuItem("Install Bootstrap…"),
            DKMenuItem("Install from File…").alternate(),
        ])
        let rows = try #require(layout.sections.first?.rows)
        #expect(rows.count == 2)
        #expect(rows[0].alternate?.item.title == "Start Headless")
        #expect(rows[0].alternate?.shortcut == "⌥⌘R")
        #expect(rows[0].alternate?.modifiers == .option)
        #expect(rows[1].alternate?.shortcut == nil)
        #expect(rows[1].alternate?.modifiers == .option)
    }

    // MARK: - NSMenu

    @Test
    func `an NSMenu carries titles, key equivalents, masks and states`() {
        let menu = DKMenu("Window") {
            DKMenuItem.header("research-26")
            DKMenuItem("Display", shortcut: "⌥⌘1").checked(true)
            DKMenuItem("Workspace", shortcut: "⌥⌘2").checked(false)
            DKMenuItem("Mixed").state(.mixed)
            DKMenuItem.separator
            DKMenuItem("Home Screen", glyph: .home, shortcut: "⇧⌘H")
            DKMenuItem("Back", shortcut: "esc")
            DKMenuItem("Zoom")
        }.makeNSMenu()

        #expect(menu.title == "Window")
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map(\.title) == ["research-26", "Display", "Workspace", "Mixed", "", "Home Screen", "Back", "Zoom"])
        #expect(menu.items[0].isSectionHeader)
        #expect(menu.items[1].keyEquivalent == "1")
        #expect(menu.items[1].keyEquivalentModifierMask == [.option, .command])
        #expect(menu.items[1].state == .on)
        #expect(menu.items[2].state == .off)
        #expect(menu.items[3].state == .mixed)
        #expect(menu.items[4].isSeparatorItem)
        #expect(menu.items[5].keyEquivalent == "h")
        #expect(menu.items[5].keyEquivalentModifierMask == [.shift, .command])
        #expect(menu.items[5].image != nil)
        #expect(menu.items[6].keyEquivalent == "\u{1B}")
        #expect(menu.items[6].keyEquivalentModifierMask == [])
        #expect(menu.items[7].keyEquivalent == "")
        #expect(menu.items[7].keyEquivalentModifierMask == [])
    }

    @Test
    func `submenus nest and keep their own titles`() throws {
        let menu = DKMenu("Machine") {
            DKMenuItem("Show in Finder")
            DKMenuItem.submenu("Logs") {
                DKMenuItem("Console Log")
                DKMenuItem("Patch Log", shortcut: "⇧⌘L")
            }
            DKMenuItem.submenu("Core Bundle", isEnabled: false) {
                DKMenuItem("Change Core Bundle…")
            }
        }.makeNSMenu()

        let logs = try #require(menu.items[1].submenu)
        #expect(menu.items[1].title == "Logs")
        #expect(logs.title == "Logs")
        #expect(logs.items.map(\.title) == ["Console Log", "Patch Log"])
        #expect(logs.items[1].keyEquivalent == "l")
        #expect(logs.items[1].keyEquivalentModifierMask == [.shift, .command])
        #expect(!menu.items[2].isEnabled)

        let alone = DKMenuItem.submenu("Logs") { DKMenuItem("Console Log") }.makeNSMenu()
        #expect(alone.title == "Logs")
        #expect(alone.items.map(\.title) == ["Console Log"])
    }

    @Test
    func `separators collapse in the NSMenu`() {
        let menu = [DKMenuItem.separator, DKMenuItem("A"), .separator, .separator, DKMenuItem("B"), .separator]
            .makeNSMenu()
        #expect(menu.items.map(\.isSeparatorItem) == [false, true, false])
    }

    @Test
    func `an item runs its closure and is its own target`() throws {
        let count = DKMenuTestCounter()
        let menu = DKMenu("Machine") {
            DKMenuItem("Start", shortcut: "⌘R") { count.value += 1 }
        }.makeNSMenu()
        let item = try #require(menu.items.first)
        #expect(item.target === item)
        #expect(item.action == #selector(DKClosureMenuItem.runHandler(_:)))
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: item)
        _ = target.perform(action, with: item)
        #expect(count.value == 2)
    }

    @Test
    func `disabled, destructive and identified items keep their flags`() {
        let menu = DKMenu("Machine") {
            DKMenuItem("Stop", shortcut: "⌘.").disabled()
            DKMenuItem("Delete…", shortcut: "⌘⌫").destructive().identifier("delete")
        }.makeNSMenu()
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[1].isEnabled)
        #expect(menu.items[1].title == "Delete…")
        #expect(menu.items[1].attributedTitle?.string == "Delete…")
        #expect(menu.items[1].identifier?.rawValue == "delete")
        #expect(menu.items[1].keyEquivalent == "\u{08}")
    }

    @Test
    func `alternates become AppKit alternates`() {
        let menu = DKMenu("Apps") {
            DKMenuItem("Start", shortcut: "⌘R")
            DKMenuItem("Start Headless").alternate()
            DKMenuItem("Install Bootstrap…")
            DKMenuItem("Install from File…").alternate()
        }.makeNSMenu()
        #expect(menu.items.map(\.isAlternate) == [false, true, false, true])
        #expect(menu.items[1].keyEquivalent == "r")
        #expect(menu.items[1].keyEquivalentModifierMask == [.option, .command])
        #expect(menu.items[2].keyEquivalentModifierMask == [])
        #expect(menu.items[3].keyEquivalent == "")
        #expect(menu.items[3].keyEquivalentModifierMask == .option)
    }

    @Test
    func `a menu-bar item opens its menu`() {
        let item = DKMenu("Capture") { DKMenuItem("Start Recording", shortcut: "⇧⌘R") }.makeMenuBarItem()
        #expect(item.title == "Capture")
        #expect(item.submenu?.items.first?.keyEquivalent == "r")
    }

    // MARK: - Preview

    @Test
    func `the preview draws submenu rows indented and alternates with their modifier`() {
        let preview = DKMenuPreview(DKMenu("Apps") {
            DKMenuItem("App Browser", shortcut: "⇧⌘A")
            DKMenuItem.separator
            DKMenuItem.header("Bootstrap")
            DKMenuItem("Install Bootstrap…")
            DKMenuItem("Install from File…").alternate()
            DKMenuItem.submenu("Logs") { DKMenuItem("Console Log") }
        })
        let described: [String] = preview.rows.map { row in
            switch row {
            case .separator: "—"
            case let .header(title, depth): "\(depth)#\(title)"
            case let .item(item, trailing, depth):
                switch trailing {
                case .none: "\(depth) \(item.title)"
                case let .shortcut(text): "\(depth) \(item.title) \(text)"
                case .submenu: "\(depth) \(item.title) >"
                }
            }
        }
        #expect(described == [
            "0 App Browser ⇧⌘A", "—", "0#Bootstrap", "0 Install Bootstrap…", "0 Install from File… ⌥",
            "0 Logs >", "1 Console Log",
        ])
        #expect(DKMenuPreview(DKMenu("Apps") { DKMenuItem.submenu("Logs") { DKMenuItem("A") } }, expandsSubmenus: false).rows.count == 1)
    }
}

@MainActor
final class DKMenuTestCounter {
    var value = 0
}
