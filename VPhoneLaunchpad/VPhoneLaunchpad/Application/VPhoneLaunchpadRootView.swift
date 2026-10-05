import SwiftUI
import VPhoneDesignKit

/// The main window: the sidebar's pages beside the page picked in it. Host
/// Setup and Bundles are pages like the others; a bundle install is the one
/// sheet over all of them.
struct VPhoneLaunchpadRootView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    #if DEBUG
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var host = model.host
        @Bindable var bundles = model.bundles
        NavigationSplitView {
            VPhoneLaunchpadSidebar()
                .navigationSplitViewColumnWidth(DK.Metric.sidebarWidth)
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.destination.localizedTitle)
        .task { await model.start() }
        // Coming back from System Settings, with or without Host Setup open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            host.refreshDeveloperTools()
        }
        .sheet(isPresented: Binding(get: { model.panel == .bundleInstall }, set: {
            if !$0 {
                model.panel = nil
            }
        })) {
            VPhoneLaunchpadInstallView()
                .environment(model)
        }
        // Host Setup and Bundles show their own errors; these cover work
        // done on another page or with none open, such as the helper update
        // on launch.
        .errorAlert($host.actionError, isEnabled: model.panel == nil && model.destination != .hostSetup)
        .errorAlert($bundles.actionError, isEnabled: model.panel == nil && model.destination != .bundles)
        #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: VPhoneLaunchpadPreview.settingsNotification)) { _ in
                openSettings()
            }
        #endif
    }

    @ViewBuilder
    private var page: some View {
        switch model.destination {
        case .machines:
            VPhoneLaunchpadMachinesView()
        case .firmwares:
            VPhoneLaunchpadFirmwaresView()
        case .disks:
            VPhoneLaunchpadDisksView()
        case .bundles:
            VPhoneLaunchpadCoreBundleView()
        case .network:
            VPhoneLaunchpadNetworkView()
        case .hostSetup:
            VPhoneLaunchpadHostSetupView()
        }
    }
}

extension View {
    /// Presents an action error as an alert and clears it when dismissed.
    func errorAlert(_ error: Binding<VPhoneLaunchpadError?>, isEnabled: Bool = true) -> some View {
        alert(
            error.wrappedValue?.message ?? "",
            isPresented: Binding(
                get: { isEnabled && error.wrappedValue != nil },
                set: {
                    if !$0 {
                        error.wrappedValue = nil
                    }
                },
            ),
            presenting: error.wrappedValue,
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.detail ?? "")
        }
    }
}
