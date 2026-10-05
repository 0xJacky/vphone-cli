import SwiftUI
import VPhoneDesignKit

/// The Disks page. Space used by machines, restore files and the IPSW cache in each library folder.
struct VPhoneLaunchpadDisksView: View {
    var body: some View {
        ContentUnavailableView("Disks", systemImage: "hammer", description: Text(verbatim: "Not built yet."))
            .navigationTitle("Disks")
    }
}
