import SwiftUI
import VPhoneDesignKit

/// The Settings window (⌘,): the app-wide preferences Launchpad keeps, one
/// tab each for General, Library, Bundles and Advanced.
///
/// The window draws its own chrome, as the main window does: DesignKit's
/// header band holds the window buttons, the tab's name as the title and the
/// row of tabs, in place of the system title bar and toolbar tabs.
struct VPhoneLaunchpadSettingsView: View {
    enum Tab: String, Hashable, CaseIterable {
        case general
        case library
        case bundles
        case advanced

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .library: String(localized: "Library")
            case .bundles: String(localized: "Bundles")
            case .advanced: String(localized: "Advanced")
            }
        }

        var glyph: DKGlyph {
            switch self {
            case .general: .gear
            case .library: .folder
            case .bundles: .bundle
            case .advanced: .sliders
            }
        }
    }

    @State private var tab = Tab.general

    private var tabs: [DKSettingsTab<Tab>] {
        Tab.allCases.map { DKSettingsTab(id: $0, title: $0.title, glyph: $0.glyph) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DKSettingsTabBar(tabs: tabs, selection: $tab, label: String(localized: "Settings"))
            page
        }
        .frame(width: 672)
        .background(DK.Palette.page)
        // The window fits the tab's height exactly, header band included.
        .dkContentUnderTitleBar()
        .dkWindowChrome()
        .toolbar(.hidden, for: .windowToolbar)
        // Not drawn; it names the window in the Window menu and VoiceOver.
        .navigationTitle(tab.title)
        #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: VPhoneLaunchpadPreview.settingsNotification)) { note in
                if let next = note.object as? Tab {
                    tab = next
                }
            }
        #endif
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .general: VPhoneLaunchpadGeneralSettings()
        case .library: VPhoneLaunchpadLibrarySettings()
        case .bundles: VPhoneLaunchpadBundleSettings()
        case .advanced: VPhoneLaunchpadAdvancedSettings()
        }
    }
}

// MARK: - Page

/// One tab's sections on the page ground. The window takes the height of
/// the tab on screen, as a settings window does.
struct VPhoneLaunchpadSettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(DK.Palette.page)
    }
}

extension VPhoneLaunchpadStatus {
    /// The DesignKit tone for a check's state, for the Settings rows.
    var settingsTone: DKTone {
        switch self {
        case .passed: .success
        case .warning: .warning
        case .failed: .danger
        case .pending: .idle
        case .running: .info
        }
    }
}

// MARK: - Help

/// The muted note under a setting, inside its card, without a divider above.
struct VPhoneLaunchpadSettingsHelp: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DK.Typeface.caption)
            .lineSpacing(3)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, DK.Space.s3)
    }
}

// MARK: - General

struct VPhoneLaunchpadGeneralSettings: View {
    @AppStorage(VPhoneLaunchpadMenuBar.key) private var showsInMenuBar = false

    var body: some View {
        VPhoneLaunchpadSettingsPage {
            DKSection(String(localized: "Menu Bar")) {
                VStack(spacing: 0) {
                    DKFormRow(String(localized: "Keep in Menu Bar"), labelWidth: 200) {
                        DKSwitch(String(localized: "Keep in Menu Bar"), isOn: $showsInMenuBar)
                    }
                    VPhoneLaunchpadSettingsHelp(String(localized: "Closing the window keeps Launchpad in the menu bar, where you can start and stop machines. The Dock icon appears only while a window or the menu is open."))
                }
            }
        }
    }
}
