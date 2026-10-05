import SwiftUI
import VPhoneDesignKit

// MARK: - Mode

/// The toolbar switch each guest tool window shows.
enum VPhoneGuestToolMode: String, CaseIterable, Identifiable {
    case read
    case write

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .read: String(localized: "Read", bundle: VPhoneLocalization.bundle)
        case .write: String(localized: "Write", bundle: VPhoneLocalization.bundle)
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .read: "1"
        case .write: "2"
        }
    }
}

struct VPhoneGuestToolModePicker: View {
    @Binding var mode: VPhoneGuestToolMode

    var body: some View {
        Picker("Mode", selection: $mode) {
            ForEach(VPhoneGuestToolMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Switch between reading from and writing to the guest (⌘1, ⌘2)")
    }
}

// MARK: - Status

struct VPhoneGuestToolStatus {
    let message: String
    let isError: Bool

    /// The status bar text tone: a failure in the danger ink.
    var tone: DKTone? {
        isError ? .danger : nil
    }
}

// MARK: - Shortcuts

/// A keyboard shortcut for a toolbar action.
struct VPhoneGuestToolShortcut {
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    var isEnabled = true
    let action: () -> Void
}

extension View {
    /// Adds keyboard shortcuts for toolbar actions. The buttons are invisible
    /// but stay in the hosting view, where AppKit routes key equivalents.
    func guestToolShortcuts(_ shortcuts: [VPhoneGuestToolShortcut]) -> some View {
        background {
            ForEach(shortcuts.indices, id: \.self) { index in
                let shortcut = shortcuts[index]
                Button(action: shortcut.action) { EmptyView() }
                    .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                    .disabled(!shortcut.isEnabled)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

