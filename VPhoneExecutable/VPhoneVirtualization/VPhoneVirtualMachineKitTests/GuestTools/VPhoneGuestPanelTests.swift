import Testing
@testable import VPhoneVirtualMachineKit

/// Which vphoned capability each guest panel needs before it can talk to the agent.
@Suite("Guest panels")
struct VPhoneGuestPanelTests {
    @Test
    func `each panel asks for the capability its endpoints live under`() {
        #expect(VPhoneGuestPanel.deviceInfo.capability == "device_info")
        #expect(VPhoneGuestPanel.processes.capability == "processes")
        #expect(VPhoneGuestPanel.console.capability == "logs")
        #expect(VPhoneGuestPanel.crashLogs.capability == "logs")
        #expect(VPhoneGuestPanel.services.capability == "services")
        #expect(VPhoneGuestPanel.controls.capability == "display")
    }
}
