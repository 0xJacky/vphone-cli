import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Window titles, sheet notes and sheet footer keys.
@Suite("DesignKit window chrome")
struct DKChromeTests {
    // MARK: - Window titles

    @Test
    func `the display window carries the machine name alone`() {
        #expect(DKVMWindowKind.display.title(machine: "research-26") == "research-26")
    }

    @Test
    func `the other three windows add their own name after an em dash`() {
        #expect(DKVMWindowKind.workspace.title(machine: "research-26") == "research-26 — Workspace")
        #expect(DKVMWindowKind.terminal.title(machine: "research-26") == "research-26 — Terminal")
        #expect(DKVMWindowKind.files.title(machine: "research-26") == "research-26 — Files")
    }

    @Test
    func `only the display window keeps the roomy title bar`() {
        let compact = DKVMWindowKind.allCases.filter(\.usesCompactTitleBar)
        #expect(compact == [.workspace, .terminal, .files])
    }

    // MARK: - Notes

    @Test
    func `a note tone takes its color from the matching status tone`() {
        #expect(DKSheetNoteTone.muted.tone == .idle)
        #expect(DKSheetNoteTone.warning.tone == .warning)
        #expect(DKSheetNoteTone.danger.tone == .danger)
    }

    @Test
    func `a status tone reads as muted unless it is a warning or a danger`() {
        for tone in DKTone.allCases {
            let expected: DKSheetNoteTone = switch tone {
            case .warning: .warning
            case .danger: .danger
            default: .muted
            }
            #expect(DKSheetNoteTone(tone) == expected, "\(tone)")
        }
    }

    @Test
    func `a note is muted unless told otherwise`() {
        #expect(DKSheetNote("Ready").tone == .muted)
    }

    // MARK: - Footer keys

    @Test
    func `Return goes to the primary button and Escape to the cancel button`() {
        let actions: [DKSheetAction] = [.cancel {}, .primary("Create") {}]
        #expect(DKSheetAction.shortcuts(for: actions) == [.cancelAction, .defaultAction])
    }

    @Test
    func `an automatic primary-looking button takes Return when nothing claims it`() {
        let actions = [
            DKSheetAction("Reveal") {},
            DKSheetAction("Save", variant: .primary) {},
            DKSheetAction("Save As", variant: .primary) {},
        ]
        #expect(DKSheetAction.shortcuts(for: actions) == [nil, .defaultAction, nil])
    }

    @Test
    func `an explicit default action wins over an earlier primary-looking button`() {
        let actions = [
            DKSheetAction("Install", variant: .primary) {},
            DKSheetAction.destructive("Erase") {},
        ]
        #expect(DKSheetAction.shortcuts(for: actions) == [nil, .defaultAction])
    }

    @Test
    func `a plain button never takes a key and each key is bound once`() {
        let actions = [
            DKSheetAction("Open", variant: .primary, role: .plain) {},
            DKSheetAction.cancel("Close") {},
            DKSheetAction.cancel("Dismiss") {},
        ]
        #expect(DKSheetAction.shortcuts(for: actions) == [nil, .cancelAction, nil])
    }

    @Test
    func `the footer keys map to the system default and cancel shortcuts`() {
        #expect(DKSheetShortcut.defaultAction.keyboardShortcut == .defaultAction)
        #expect(DKSheetShortcut.cancelAction.keyboardShortcut == .cancelAction)
    }

    // MARK: - Sheet height

    @Test
    func `a sheet is as tall as its content until it reaches its maximum`() {
        #expect(DKSheetMetrics.bodyHeight(content: 300, chrome: 120, maxHeight: 800) == 300)
        #expect(DKSheetMetrics.bodyHeight(content: 900, chrome: 120, maxHeight: 800) == 680)
        #expect(DKSheetMetrics.bodyHeight(content: 900, chrome: 900, maxHeight: 800) == 0)
    }
}
