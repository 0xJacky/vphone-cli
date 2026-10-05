import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// How Controls reads the guest's values and builds what it sends.
@MainActor
@Suite("Controls")
struct VPhoneControlsModelTests {
    private func model(connected: Bool = true) -> VPhoneControlsModel {
        let model = VPhoneControlsModel(control: VPhoneGuestControl())
        model.isConnected = connected
        return model
    }

    // MARK: - Reading

    @Test
    func `rotation reads the interface orientation and lock`() {
        let model = model()
        model.apply(rotationResult: ["degrees": 90, "locked": true])
        #expect(model.orientation == .landscapeLeft)
        #expect(model.rotationLocked == true)
        model.apply(rotationResult: ["degrees": 270])
        #expect(model.orientation == .landscapeRight)
        #expect(model.rotationLocked == nil)
        // An angle the segment does not offer reads as unavailable.
        model.apply(rotationResult: ["degrees": 45])
        #expect(model.orientation == nil)
    }

    @Test
    func `volume clamps to the slider and an unreadable category reads as unavailable`() {
        let model = model()
        model.apply(volumeResult: ["volume": 1.4, "category": "Ringtone"])
        #expect(model.volumeCategory == .ringer)
        #expect(model.guestVolume == 1)
        #expect(model.volume == 1)
        model.apply(volumeResult: ["volume": -1, "category": "Unknown"])
        #expect(model.volumeCategory == .ringer)
        #expect(model.guestVolume == nil)
        #expect(model.volume == 0)
    }

    @Test
    func `brightness clamps and auto stays unknown when unreported`() {
        let model = model()
        model.apply(brightnessResult: ["value": 1.5])
        #expect(model.guestBrightness == 1)
        #expect(model.autoBrightness == nil)
        model.apply(brightnessResult: ["value": -0.2, "auto": true])
        #expect(model.guestBrightness == 0)
        #expect(model.autoBrightness == true)
    }

    @Test
    func `the active session names its category and level, or None`() {
        let model = model()
        #expect(model.activeSessionText == "—")
        model.apply(audioStateResult: ["active_category": "", "active_volume": 0.6, "active_muted": false])
        #expect(model.activeSessionText == "None")
        model.apply(audioStateResult: ["active_category": "Audio/Video"])
        #expect(model.activeSessionText == "Audio/Video")
        model.apply(audioStateResult: ["active_category": "Audio/Video", "active_volume": 0.6, "active_muted": false])
        #expect(model.activeSessionText.hasPrefix("Audio/Video, "))
        #expect(model.activeSessionText.contains("60"))
        #expect(!model.activeSessionText.hasSuffix("muted"))
        model.apply(audioStateResult: ["active_category": "Ringtone", "active_volume": 0.4, "active_muted": true])
        #expect(model.activeSessionText.hasPrefix("Ringtone, "))
        #expect(model.activeSessionText.hasSuffix(", muted"))
    }

    // MARK: - Sending

    @Test
    func `special keys carry the held modifiers in press order`() {
        let model = model()
        #expect(model.keyName(.left) == "left")
        model.modifiers = [.command, .shift]
        #expect(model.keyName(.left) == "shift+cmd+left")
        model.modifiers = [.option, .control, .command, .shift]
        #expect(model.keyName(.return) == "ctrl+alt+shift+cmd+return")
    }

    @Test
    func `text can be sent only while connected, non-empty and within 64 KiB`() {
        let model = model()
        #expect(!model.canSendText)
        model.keyboardText = "hello"
        #expect(model.canSendText)
        model.keyboardText = String(repeating: "a", count: 64 * 1024 + 1)
        #expect(!model.canSendText)
        model.keyboardText = "hello"
        model.isConnected = false
        #expect(!model.canSendText)
        #expect(!model.canWrite)
    }

    @Test
    func `a notification needs a name that is not just spaces`() {
        let model = model()
        model.notificationName = "   "
        #expect(!model.canUseNotification)
        model.notificationName = " com.apple.springboard.lockcomplete "
        #expect(model.canUseNotification)
    }

    @Test
    func `orientations, categories and keys name what the guest parses`() {
        #expect(VPhoneControlsOrientation.allCases.map(\.spec) == ["portrait", "landscape-left", "landscape-right", "upside-down"])
        #expect(VPhoneControlsOrientation(degrees: 180) == .upsideDown)
        #expect(VPhoneControlsVolumeCategory.allCases.map(\.rawValue) == ["Audio/Video", "Ringtone"])
        #expect(VPhoneControlsKey.allCases.filter(\.isArrow) == [.left, .up, .down, .right])
        #expect(VPhoneControlsModifier.allCases.map(\.symbol) == ["⌃", "⌥", "⇧", "⌘"])
    }
}
