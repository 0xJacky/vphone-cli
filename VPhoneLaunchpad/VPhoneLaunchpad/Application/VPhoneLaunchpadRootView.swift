import SwiftUI
import VPhoneDesignKit

/// The main window: the sidebar's pages beside the page picked in it. Host
/// Setup and Bundles are pages like the others; a bundle install is the one
/// sheet over all of them.
///
/// The window draws all of its chrome: there is no system title bar, toolbar
/// or window buttons. The sidebar's top band holds DesignKit's window
/// buttons, and each page's header runs to the window's top edge beside it,
/// its title level with the buttons. View › Hide Sidebar (⌃⌘S) and Hide
/// Inspector (⌥⌘I) replace a toolbar's toggles; with the sidebar hidden the
/// buttons lead the page header instead.
struct VPhoneLaunchpadRootView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    #if DEBUG
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var host = model.host
        @Bindable var bundles = model.bundles
        HStack(spacing: 0) {
            if model.showsSidebar {
                VPhoneLaunchpadSidebar()
            }
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.dkPageHeaderWindowControls, !model.showsSidebar)
        }
        .frame(minWidth: VPhoneLaunchpadWindowSize.minimum.width, minHeight: VPhoneLaunchpadWindowSize.minimum.height)
        // The content runs under the transparent title bar to the window's
        // top edge; the headers and the sidebar band take its place.
        .ignoresSafeArea(.container, edges: .top)
        .dkWindowChrome()
        .toolbar(.hidden, for: .windowToolbar)
        // Not drawn, but it names the window in the Window menu, Mission
        // Control and VoiceOver.
        .navigationTitle(model.destination.title)
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
            VPhoneLaunchpadHostSetupView(onReviewDisks: { model.show(.disks) })
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
