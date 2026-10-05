import SwiftUI
import VPhoneDesignKit

/// The Firmwares page. The IPSWs Launchpad has downloaded, and the restore files prepared for each machine.
struct VPhoneLaunchpadFirmwaresView: View {
    var body: some View {
        ContentUnavailableView("Firmwares", systemImage: "hammer", description: Text(verbatim: "Not built yet."))
            .navigationTitle("Firmwares")
    }
}
