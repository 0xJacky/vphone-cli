import SwiftUI
import VPhoneDesignKit

/// The Network page. Each machine's network mode, address and port forwards, and the addresses the Mac holds for guests.
struct VPhoneLaunchpadNetworkView: View {
    var body: some View {
        ContentUnavailableView("Network", systemImage: "hammer", description: Text(verbatim: "Not built yet."))
            .navigationTitle("Network")
    }
}
