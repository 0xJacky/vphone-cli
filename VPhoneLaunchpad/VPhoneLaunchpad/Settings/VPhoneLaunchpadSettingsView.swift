import SwiftUI
import VPhoneDesignKit

/// The Settings window (⌘,): the app-wide preferences Launchpad keeps, one
/// tab each for General, Library, Bundles and Advanced.
struct VPhoneLaunchpadSettingsView: View {
    enum Tab: String, Hashable, CaseIterable {
        case general
        case library
        case bundles
        case advanced
    }

    @State private var tab = Tab.general

    var body: some View {
        TabView(selection: $tab) {
            VPhoneLaunchpadGeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            VPhoneLaunchpadLibrarySettings()
                .tabItem { Label("Library", systemImage: "folder") }
                .tag(Tab.library)
            VPhoneLaunchpadBundleSettings()
                .tabItem { Label("Bundles", systemImage: "shippingbox") }
                .tag(Tab.bundles)
            VPhoneLaunchpadAdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(Tab.advanced)
        }
        .frame(width: 672)
        #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: VPhoneLaunchpadPreview.settingsNotification)) { note in
                if let next = note.object as? Tab {
                    tab = next
                }
            }
        #endif
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
